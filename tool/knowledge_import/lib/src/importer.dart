import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(List<String> command, Directory? cwd);

/// Resolves reviewed public sources and applies only explicitly reviewed files.
///
/// The importer never executes downloaded text. Raw source repositories and
/// staging files live under the ignored `.wayfinder-import/` directory; only
/// locks and authored knowledge belong in the example project.
final class KnowledgeImporter {
  KnowledgeImporter({ProcessRunner? process}) : _process = process ?? _run;

  final ProcessRunner _process;

  Future<SourceLockDocument> resolve(Directory project) async {
    final manifestFile = File(p.join(project.path, 'sources.json'));
    final manifestText = await manifestFile.readAsString();
    final manifest = SourceManifest.fromJson(manifestText);
    final cache = Directory(p.join(project.path, '.wayfinder-import', 'cache'));
    await cache.create(recursive: true);
    final resolved = <ResolvedSource>[];
    for (final source in manifest.sources.where((source) => source.enabled)) {
      resolved.add(await _resolveSource(source, cache));
    }
    final lock = SourceLockDocument(
      version: 1,
      manifestSha256: _sha256(manifestText),
      resolvedAt: DateTime.now().toUtc().toIso8601String(),
      sources: resolved,
    );
    await _writeJson(
      File(p.join(project.path, 'sources.lock.json')),
      lock.toJson(),
    );
    return lock;
  }

  Future<File> plan(Directory project) async {
    final lock = await _readLock(project);
    final output = File(p.join(project.path, '.wayfinder-import', 'plan.json'));
    final value = <String, Object?>{
      'version': 1,
      'source_lock_sha256': _sha256(jsonEncode(lock.toJson())),
      'sources': lock.sources
          .map(
            (source) => <String, Object?>{
              'id': source.id,
              'commit': source.commit,
              'adapter': source.adapter,
              'files': source.files
                  .map((file) => file.path)
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
      'changes': const <Object?>[],
      'status': 'awaiting-reviewed-authoring',
    };
    await _writeJson(output, value);
    return output;
  }

  Future<void> apply(Directory project, File changeSet) async {
    final value = jsonDecode(await changeSet.readAsString());
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['changes'] is! List) {
      throw const FormatException(
        'A change set must declare version 1 and changes.',
      );
    }
    final root = p.normalize(project.absolute.path);
    final writes = <({File file, String content})>[];
    for (final raw in (value['changes'] as List)) {
      if (raw is! Map<String, dynamic>)
        throw const FormatException('Each change must be an object.');
      final relative = raw['path'];
      final content = raw['content'];
      if (relative is! String ||
          content is! String ||
          relative.startsWith('/') ||
          relative.contains('\\') ||
          relative.split('/').contains('..')) {
        throw const FormatException(
          'Change paths must be safe project-relative paths.',
        );
      }
      final file = File(p.join(root, relative));
      if (!p.isWithin(root, file.absolute.path) && file.absolute.path != root)
        throw FormatException('Change escapes the project: $relative');
      final expected = raw['expected_sha256'] as String?;
      if (await file.exists()) {
        final current = _sha256(await file.readAsString());
        if (expected == null || current != expected)
          throw FormatException(
            'Stale change set for $relative; refusing to overwrite.',
          );
      } else if (expected != null) {
        throw FormatException('Expected existing file is missing: $relative');
      }
      writes.add((file: file, content: content));
    }
    for (final write in writes) {
      await write.file.parent.create(recursive: true);
      final temporary = File(
        '${write.file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      await temporary.writeAsString(write.content, flush: true);
      await temporary.rename(write.file.path);
    }
  }

  Future<List<String>> check(Directory project) async {
    final findings = <String>[];
    final manifestFile = File(p.join(project.path, 'sources.json'));
    final lockFile = File(p.join(project.path, 'sources.lock.json'));
    if (!await manifestFile.exists()) findings.add('sources.json is missing.');
    if (!await lockFile.exists()) findings.add('sources.lock.json is missing.');
    if (findings.isNotEmpty) return findings;
    final manifestText = await manifestFile.readAsString();
    final manifest = SourceManifest.fromJson(manifestText);
    final lock = SourceLockDocument.fromJson(
      jsonDecode(await lockFile.readAsString()),
    );
    if (lock.manifestSha256 != _sha256(manifestText))
      findings.add('Source lock is stale for sources.json.');
    final expected = manifest.sources
        .where((source) => source.enabled)
        .map((source) => source.id)
        .toSet();
    final actual = lock.sources.map((source) => source.id).toSet();
    if (expected.length != actual.length || !expected.containsAll(actual))
      findings.add('Source lock does not match enabled source IDs.');
    for (final source in lock.sources) {
      if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(source.commit))
        findings.add('Invalid commit for ${source.id}.');
      for (final file in source.files) {
        if (file.path.split('/').contains('..') || file.path.startsWith('/'))
          findings.add('Unsafe locked source path: ${source.id}:${file.path}');
      }
    }
    return findings;
  }

  Future<ResolvedSource> _resolveSource(
    SourceSpec source,
    Directory cache,
  ) async {
    final destination = Directory(p.join(cache.path, source.id));
    if (!await destination.exists()) {
      final result = await _process([
        'git',
        'clone',
        '--mirror',
        '--',
        source.repository,
        destination.path,
      ], null);
      _requireGit(result, 'clone ${source.id}');
    } else {
      final result = await _process([
        'git',
        'remote',
        'update',
        '--prune',
      ], destination);
      _requireGit(result, 'refresh ${source.id}');
    }
    final commitResult = await _process([
      'git',
      'rev-parse',
      '${source.ref}^{commit}',
    ], destination);
    _requireGit(commitResult, 'resolve ${source.id}:${source.ref}');
    final commit = commitResult.stdout.trim();
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit))
      throw FormatException('Invalid commit for ${source.id}.');
    final files = <SourceFileLock>[];
    for (final path in source.paths) {
      final result = await _process([
        'git',
        'show',
        '$commit:$path',
      ], destination);
      _requireGit(result, 'read ${source.id}:$path');
      final bytes = utf8.encode(result.stdout);
      files.add(
        SourceFileLock(
          path: path,
          sha256: sha256.convert(bytes).toString(),
          bytes: bytes.length,
        ),
      );
    }
    return ResolvedSource(
      id: source.id,
      repository: source.repository,
      ref: source.ref,
      commit: commit,
      adapter: source.adapter,
      files: files,
      licenseEvidence: source.licenseEvidence,
    );
  }

  Future<SourceLockDocument> _readLock(Directory project) async =>
      SourceLockDocument.fromJson(
        jsonDecode(
          await File(p.join(project.path, 'sources.lock.json')).readAsString(),
        ),
      );

  static Future<ProcessResult> _run(List<String> command, Directory? cwd) =>
      Process.run(
        command.first,
        command.skip(1).toList(growable: false),
        workingDirectory: cwd?.path,
      );
  static void _requireGit(ProcessResult result, String operation) {
    if (result.exitCode != 0)
      throw ProcessException(
        'git',
        const [],
        'Failed to $operation: ${result.stderr}',
      );
  }

  static String _sha256(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static Future<void> _writeJson(File file, Object value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    );
  }
}

final class SourceLockDocument {
  const SourceLockDocument({
    required this.version,
    required this.manifestSha256,
    required this.resolvedAt,
    required this.sources,
  });

  factory SourceLockDocument.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['sources'] is! List)
      throw const FormatException('Invalid source lock.');
    return SourceLockDocument(
      version: 1,
      manifestSha256: value['manifest_sha256'] as String,
      resolvedAt: value['resolved_at'] as String,
      sources: (value['sources'] as List)
          .map((item) {
            final json = item as Map<String, dynamic>;
            return ResolvedSource(
              id: json['id'] as String,
              repository: json['repository'] as String,
              ref: json['ref'] as String,
              commit: json['commit'] as String,
              adapter: json['adapter'] as String,
              licenseEvidence: json['license_evidence'] as String?,
              files: (json['files'] as List)
                  .map((file) {
                    final f = file as Map<String, dynamic>;
                    return SourceFileLock(
                      path: f['path'] as String,
                      sha256: f['sha256'] as String,
                      bytes: f['bytes'] as int,
                    );
                  })
                  .toList(growable: false),
            );
          })
          .toList(growable: false),
    );
  }

  final int version;
  final String manifestSha256;
  final String resolvedAt;
  final List<ResolvedSource> sources;
  Map<String, Object?> toJson() => {
    'version': version,
    'manifest_sha256': manifestSha256,
    'resolved_at': resolvedAt,
    'sources': sources.map((source) => source.toJson()).toList(growable: false),
  };
}

Future<int> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project', defaultsTo: '../../examples/flutter-knowledge')
    ..addOption('changeset');
  final parsed = parser.parse(arguments);
  final command = parsed.rest.length == 1 ? parsed.rest.single : null;
  if (command == null ||
      !{'resolve', 'plan', 'apply', 'check'}.contains(command)) {
    stderr.writeln(
      'Usage: dart run bin/knowledge_import.dart <resolve|plan|apply|check> --project <path> [--changeset <path>]',
    );
    return 64;
  }
  final project = Directory(parsed['project'] as String);
  final importer = KnowledgeImporter();
  try {
    switch (command) {
      case 'resolve':
        final lock = await importer.resolve(project);
        stdout.writeln(
          'Resolved ${lock.sources.length} sources to ${p.join(project.path, 'sources.lock.json')}.',
        );
      case 'plan':
        stdout.writeln('Plan: ${(await importer.plan(project)).path}');
      case 'apply':
        final path = parsed['changeset'] as String?;
        if (path == null)
          throw const FormatException('--changeset is required for apply.');
        await importer.apply(project, File(path));
        stdout.writeln('Applied reviewed change set.');
      case 'check':
        final findings = await importer.check(project);
        if (findings.isNotEmpty) {
          for (final finding in findings) stderr.writeln(finding);
          return 1;
        }
        stdout.writeln('Source manifest and lock are consistent.');
    }
    return 0;
  } on Object catch (error) {
    stderr.writeln(error);
    return 1;
  }
}
