import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'file_lock.dart';
import 'git.dart';

/// Why a managed Profile cache directory can be collected.
enum ProfileMirrorPruneReason {
  /// A directory listing establishes that the local source is gone.
  missingSource,

  /// No recorded use (or first observation of a legacy mirror) is recent.
  unused,

  /// An owned clone staging directory has outlived its retention period.
  abandonedTemporary,
}

/// One eligible mirror or owned clone staging directory.
final class ProfileMirrorPruneEntry {
  const ProfileMirrorPruneEntry({required this.path, required this.reason});

  final String path;
  final ProfileMirrorPruneReason reason;
}

/// A cache entry whose inspection or deletion failed. Other entries proceed.
final class ProfileMirrorPruneError {
  const ProfileMirrorPruneError({required this.path, required this.message});

  final String path;
  final String message;
}

/// Results of a mirror collection pass. Lists are immutable.
final class ProfileMirrorPruneResult {
  ProfileMirrorPruneResult({
    required List<ProfileMirrorPruneEntry> candidates,
    required List<ProfileMirrorPruneEntry> removed,
    required List<String> busy,
    required List<ProfileMirrorPruneError> errors,
  }) : candidates = List.unmodifiable(candidates),
       removed = List.unmodifiable(removed),
       busy = List.unmodifiable(busy),
       errors = List.unmodifiable(errors);

  /// Eligible entries, including any whose deletion subsequently failed.
  final List<ProfileMirrorPruneEntry> candidates;

  /// Directories successfully deleted; empty for a dry run.
  final List<ProfileMirrorPruneEntry> removed;

  /// Entries skipped because their governing mirror lock was held.
  final List<String> busy;

  final List<ProfileMirrorPruneError> errors;
}

/// Resolver implementation detail. All writes require the sibling mirror
/// lock; metadata lives outside the tree so partial deletion stays retryable.
final class ProfileMirrorCache {
  ProfileMirrorCache(this.dataDirectory, this.git);

  final Directory dataDirectory;
  final GitRunner git;

  static final _mirrorName = RegExp(r'^[0-9a-f]{64}$');
  static final _temporaryName = RegExp(r'^([0-9a-f]{64})\.tmp-\d+-(\d+)$');

  static File _metadata(Directory directory) =>
      File('${directory.path}.metadata.json');

  Future<void> recordUse(Directory mirror, String location) async {
    if (await FileSystemEntity.type(mirror.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    await _write(_metadata(mirror), {
      'version': 1,
      'location': location,
      'last_used': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Called before clone under the destination mirror's lock. Old staging
  /// names alone do not prove ownership and are deliberately left alone.
  Future<void> recordTemporary(Directory temporary) async {
    final match = _temporaryName.firstMatch(p.basename(temporary.path))!;
    await _write(_metadata(temporary), {
      'version': 1,
      'mirror': match[1],
      'created_at': DateTime.fromMicrosecondsSinceEpoch(
        int.parse(match[2]!),
        isUtc: true,
      ).toIso8601String(),
    });
  }

  Future<void> forgetTemporary(Directory temporary) async {
    final file = _metadata(temporary);
    if (await file.exists()) await file.delete();
  }

  Future<ProfileMirrorPruneResult> prune({
    required Duration unusedFor,
    required bool dryRun,
  }) async {
    if (unusedFor.isNegative) {
      throw ArgumentError.value(unusedFor, 'unusedFor', 'must not be negative');
    }
    final candidates = <ProfileMirrorPruneEntry>[];
    final removed = <ProfileMirrorPruneEntry>[];
    final busy = <String>[];
    final errors = <ProfileMirrorPruneError>[];
    final directory = Directory(p.join(dataDirectory.path, 'profiles'));
    final now = DateTime.now().toUtc();
    try {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.directory) {
        final entries = await directory.list(followLinks: false).toList();
        entries.sort((a, b) => a.path.compareTo(b.path));
        for (final entry in entries) {
          if (entry is! Directory) continue;
          final name = p.basename(entry.path);
          final temporary = _temporaryName.firstMatch(name);
          if (!_mirrorName.hasMatch(name) && temporary == null) continue;
          WayfinderFileLock? held;
          try {
            final lock = File(
              p.join(directory.path, '${temporary?[1] ?? name}.lock'),
            );
            final lockType = await FileSystemEntity.type(
              lock.path,
              followLinks: false,
            );
            if (lockType != FileSystemEntityType.file &&
                lockType != FileSystemEntityType.notFound) {
              throw FileSystemException(
                'Mirror lock is not a regular file',
                lock.path,
              );
            }
            held = await WayfinderFileLock.tryExclusive(lock, create: !dryRun);
            if (held == null &&
                (!dryRun || lockType != FileSystemEntityType.notFound)) {
              busy.add(entry.path);
              continue;
            }
            // Recheck the path and eligibility after taking the same lock
            // planners use. A completed planner may just have used it.
            if (await FileSystemEntity.type(entry.path, followLinks: false) !=
                FileSystemEntityType.directory) {
              continue;
            }
            final record = await _read(_metadata(entry));
            final ProfileMirrorPruneReason? reason;
            Map<String, Object?>? mirrorRecord;
            if (temporary != null) {
              if (record == null) continue;
              final created = _time(record['created_at']);
              if (record['version'] != 1 ||
                  record['mirror'] != temporary[1] ||
                  created == null ||
                  created.microsecondsSinceEpoch != int.parse(temporary[2]!)) {
                throw const FormatException(
                  'Unrecognized clone staging metadata',
                );
              }
              reason = now.difference(created) >= unusedFor
                  ? ProfileMirrorPruneReason.abandonedTemporary
                  : null;
            } else {
              mirrorRecord = record ?? await _observe(entry, now);
              reason = await _eligible(
                mirrorRecord,
                name,
                now,
                unusedFor,
                firstObservation: record == null,
              );
              if (!dryRun && record == null) {
                await _write(_metadata(entry), mirrorRecord);
              }
            }
            if (reason == null) continue;
            final candidate = ProfileMirrorPruneEntry(
              path: entry.path,
              reason: reason,
            );
            candidates.add(candidate);
            if (dryRun) continue;
            if (mirrorRecord != null) {
              // Keep eligibility even if Windows deletes config before
              // encountering an open file elsewhere in the tree.
              await _write(_metadata(entry), {
                ...mirrorRecord,
                'deleting': reason.name,
              });
            }
            await entry.delete(recursive: true);
            removed.add(candidate);
            await _metadata(entry).delete();
            // Retain the lock inode: another planner may already have it open.
          } on Exception catch (error) {
            errors.add(
              ProfileMirrorPruneError(path: entry.path, message: '$error'),
            );
          } finally {
            await held?.release();
          }
        }
      } else if (type != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Profile cache is not a directory',
          directory.path,
        );
      }
    } on FileSystemException catch (error) {
      errors.add(
        ProfileMirrorPruneError(path: directory.path, message: '$error'),
      );
    }
    return ProfileMirrorPruneResult(
      candidates: candidates,
      removed: removed,
      busy: busy,
      errors: errors,
    );
  }

  Future<Map<String, Object?>> _observe(Directory mirror, DateTime now) async {
    // Config lookup only: never contact origin, and do not read global config
    // or expand includes while discovering a legacy entry's source. Pin the
    // Git directory so an invalid entry cannot discover an enclosing repo.
    final result = await git([
      '--git-dir',
      '.',
      'config',
      '--null',
      '--local',
      '--no-includes',
      '--get',
      'remote.origin.url',
    ], workingDirectory: mirror.path);
    final text = result.text;
    if (result.exitCode != 0 || text.length < 2 || !text.endsWith('\u0000')) {
      throw const FormatException('Cannot establish legacy mirror origin');
    }
    return {
      'version': 1,
      'location': text.substring(0, text.length - 1),
      'observed_at': now.toIso8601String(),
    };
  }

  Future<ProfileMirrorPruneReason?> _eligible(
    Map<String, Object?> record,
    String key,
    DateTime now,
    Duration unusedFor, {
    required bool firstObservation,
  }) async {
    final location = record['location'];
    final used = _time(record['last_used']);
    final observed = _time(record['observed_at']);
    if (record['version'] != 1 ||
        location is! String ||
        sha256.convert(utf8.encode(location)).toString() != key ||
        (used == null && observed == null) ||
        (record.containsKey('last_used') && used == null) ||
        (record.containsKey('observed_at') && observed == null)) {
      throw const FormatException('Unrecognized mirror metadata');
    }
    if (record['deleting'] case final String reason) {
      return switch (reason) {
        'missingSource' => ProfileMirrorPruneReason.missingSource,
        'unused' => ProfileMirrorPruneReason.unused,
        _ => throw const FormatException('Unrecognized mirror deletion record'),
      };
    }
    if (!firstObservation && now.difference(used ?? observed!) >= unusedFor) {
      return ProfileMirrorPruneReason.unused;
    }
    final local = _localPath(location);
    return local != null && await _demonstrablyMissing(local)
        ? ProfileMirrorPruneReason.missingSource
        : null;
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static String? _localPath(String location) {
    // A foreign drive or UNC path cannot be probed on POSIX. In particular,
    // do not reinterpret a Windows drive as a URI scheme or a relative path.
    if (p.windows.isAbsolute(location) &&
        (!p.posix.isAbsolute(location) || location.startsWith('//'))) {
      return Platform.isWindows ? location : null;
    }
    if (p.isAbsolute(location)) return location;
    final uri = Uri.tryParse(location);
    if (uri == null || uri.scheme != 'file') return null;
    if (uri.host.isNotEmpty && uri.host != 'localhost' && !Platform.isWindows) {
      return null;
    }
    return uri.toFilePath(windows: Platform.isWindows);
  }

  /// exists/type can return false/notFound for permission errors too. Only
  /// a successful parent listing proves absence. Recurse if an ancestor is
  /// gone; access errors propagate rather than turning into deletion evidence.
  static Future<bool> _demonstrablyMissing(String path) async {
    path = p.normalize(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    final parent = p.dirname(path);
    if (parent == path) return false;
    try {
      await for (final entry in Directory(parent).list(followLinks: false)) {
        if (p.equals(entry.path, path)) return false;
      }
      return true;
    } on PathNotFoundException {
      return _demonstrablyMissing(parent);
    }
  }

  static Future<Map<String, Object?>?> _read(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Metadata is not a regular file', file.path);
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) {
      throw const FormatException('Unrecognized mirror metadata');
    }
    return value;
  }

  static Future<void> _write(File file, Map<String, Object?> value) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw FileSystemException('Metadata is not a regular file', file.path);
    }
    final temporary = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString('${jsonEncode(value)}\n', flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
