import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../project/profile_skills.dart';

/// What adoption read of a project, by project-relative POSIX path: each
/// entry's type and a digest of its bytes, or of everything below a
/// directory. Applying reads the same paths again and refuses the plan when
/// any differs, so it never writes over a change it did not plan.
final class AdoptionInputs {
  const AdoptionInputs._(this.entries);

  final Map<String, String> entries;

  /// The entry of a host input that resolves, through a symbolic link,
  /// outside the project, to the project directory itself or into `.git`.
  /// Nothing there is read; planning refuses it.
  static const outside = 'outside';

  /// The entry of a host input that passes through more symbolic links than
  /// resolve, as a loop of links does; planning refuses it.
  static const unresolved = 'unresolved';

  /// Reads the files adoption writes or checks, the bundle directory and
  /// every ancestor of it, the agent skill roots, and each of the host's
  /// [hostInputs] with everything below it.
  ///
  /// A host input counts with what it resolves to: every symbolic link in
  /// its path, its own included, is followed, and the entry names the
  /// project path it resolves to, so an edit made through a link, or a link
  /// that moves, changes the entry. A link below a directory input counts by
  /// its target, as adoption's own paths do.
  static Future<AdoptionInputs> read(
    String projectRoot,
    String bundle, {
    List<String> hostInputs = const [],
  }) async {
    final segments = p.posix.split(bundle);
    final realRoot = hostInputs.isEmpty ? null : await _realPath(projectRoot);
    final entries = <String, String>{
      for (final path in const [
        'wayfinder.json',
        'wayfinder.lock',
        '.gitignore',
        '.claude',
        '.agents',
      ])
        path: await _describe(projectRoot, path, recursive: false),
      for (var index = 1; index < segments.length; index++)
        p.posix.joinAll(segments.take(index)): await _describe(
          projectRoot,
          p.posix.joinAll(segments.take(index)),
          recursive: false,
        ),
      bundle: await _describe(projectRoot, bundle, recursive: true),
      for (final root in ProfileSkills.roots)
        root: await _describe(projectRoot, root, recursive: true),
      for (final path in hostInputs)
        path: await _describeHostInput(projectRoot, realRoot, path),
    };
    return AdoptionInputs._(Map.unmodifiable(entries));
  }

  /// Whether the POSIX [path] has a `.git` segment, in any case, since a
  /// case-insensitive filesystem reads `.GIT` as `.git`.
  static bool inGit(String path) =>
      p.posix.split(path).any((segment) => segment.toLowerCase() == '.git');

  /// The paths whose entries differ from [other]'s, in path order.
  List<String> changedSince(AdoptionInputs other) => [
    for (final path in {...entries.keys, ...other.entries.keys}.sorted())
      if (entries[path] != other.entries[path]) path,
  ];

  /// The host input [path] as what it resolves to: [outside] or
  /// [unresolved] when it may not be read, else the entry of the project
  /// path it resolves to, prefixed with that path when a link led there.
  static Future<String> _describeHostInput(
    String projectRoot,
    String? realRoot,
    String path,
  ) async {
    final real = await _realPath(
      p.joinAll([projectRoot, ...p.posix.split(path)]),
    );
    if (real == null || realRoot == null) return unresolved;
    if (!p.isWithin(realRoot, real)) return outside;
    final resolved = p.posix.joinAll(p.split(p.relative(real, from: realRoot)));
    if (inGit(resolved)) return outside;
    final entry = await _describe(realRoot, resolved, recursive: true);
    return resolved == path ? entry : 'resolves $resolved $entry';
  }

  /// The links [_realPath] follows before it gives up, as the system does.
  static const _maxLinks = 40;

  /// The absolute [path] with every symbolic link in it resolved, its last
  /// segment's included, as the system resolves it; a part that does not
  /// exist is kept as written, so a missing file, or a link to one,
  /// resolves too. Null when it passes through more than [_maxLinks] links,
  /// as a loop does.
  static Future<String?> _realPath(String path) async {
    final pending = Queue.of(p.split(path).skip(1));
    var resolved = p.rootPrefix(path);
    var links = 0;
    while (pending.isNotEmpty) {
      final segment = pending.removeFirst();
      if (segment == '.') continue;
      if (segment == '..') {
        resolved = p.dirname(resolved);
        continue;
      }
      final next = p.join(resolved, segment);
      if (await FileSystemEntity.type(next, followLinks: false) !=
          FileSystemEntityType.link) {
        resolved = next;
        continue;
      }
      if (++links > _maxLinks) return null;
      final target = await Link(next).target();
      final parts = p.split(target);
      if (p.isAbsolute(target)) {
        resolved = p.rootPrefix(target);
        parts.removeAt(0);
      }
      for (final part in parts.reversed) {
        pending.addFirst(part);
      }
    }
    return resolved;
  }

  static Future<String> _describe(
    String projectRoot,
    String path, {
    required bool recursive,
  }) async {
    final native = p.joinAll([projectRoot, ...p.posix.split(path)]);
    switch (await FileSystemEntity.type(native, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return 'absent';
      case FileSystemEntityType.file:
        return 'file ${await _digest(File(native))}';
      case FileSystemEntityType.link:
        return 'link ${await Link(native).target()}';
      case FileSystemEntityType.directory when !recursive:
        return 'directory';
      case FileSystemEntityType.directory:
        final lines = <String>[];
        await for (final entity in Directory(
          native,
        ).list(recursive: true, followLinks: false)) {
          final relative = p.posix.joinAll(
            p.split(p.relative(entity.path, from: native)),
          );
          lines.add(switch (entity) {
            File() => '$relative file ${await _digest(entity)}',
            Link() => '$relative link ${await entity.target()}',
            _ => '$relative directory',
          });
        }
        lines.sort();
        return 'directory ${sha256.convert(utf8.encode(lines.join('\n')))}';
      default:
        return 'other';
    }
  }

  /// [file]'s SHA-256, read as a stream, so a large file never sits in
  /// memory whole.
  static Future<Digest> _digest(File file) =>
      sha256.bind(file.openRead()).single;
}
