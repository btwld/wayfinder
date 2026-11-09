import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../knowledge.dart';
import '../../wayfinder_config.dart';
import 'projection.dart';

/// Filesystem loader for a granted project, captured read-only with no Profile resolution,
/// fetching, model, cache writes or symlink following. All bytes are retained.
///
/// Bounds apply to raw capture allocation, not just individual read calls.
/// Initial/changed capture compares two byte manifests, retrying once on
/// ordinary edits; idle refresh reuses the last capture after one matching scan.
/// This is not a filesystem transaction or an adversarial-race guarantee.
final class LocalKnowledgeProject extends CapturedKnowledgeProject {
  LocalKnowledgeProject._(super.id, this._source)
    : super(capture: _source.capture);
  final _LocalSource _source;

  /// Invalidates leases, drains work and drops the reusable capture.
  @override
  Future<void> close() async {
    await super.close();
    _source._previous = null;
  }

  /// [bundleIds] optionally binds project-relative bundle paths to host-stable
  /// identities. Otherwise IDs are explicitly location-bound, not portable.
  /// [includeHiddenDirectories] opts into dot-prefixed directories within bundles;
  /// configuration and lock files remain captured independently of that policy.
  /// Existing projects without bundles return an empty snapshot; absent roots
  /// and missing configured bundles fail with [KnowledgeFailureCode.notFound].
  static Future<LocalKnowledgeProject> open({
    required Directory root,
    required String id,
    Map<String, String> bundleIds = const {},
    int maxFileBytes = 16 * 1024 * 1024,
    int maxCaptureBytes = 64 * 1024 * 1024,
    bool includeHiddenDirectories = false,
  }) async {
    knowledgeIdentifier(id, 'project');
    if (maxFileBytes <= 0 || maxCaptureBytes <= 0) {
      throw ArgumentError('Capture bounds must be positive.');
    }
    for (final entry in bundleIds.entries) {
      knowledgeRelativePath(entry.key);
      knowledgeIdentifier(entry.value, 'bundle');
    }
    try {
      if (await FileSystemEntity.type(root.path) ==
          FileSystemEntityType.notFound) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.notFound,
          'open',
          'The granted project directory does not exist.',
        );
      }
      final canonical = await root.resolveSymbolicLinks();
      return LocalKnowledgeProject._(
        id,
        _LocalSource(
          canonical,
          Map.unmodifiable(bundleIds),
          maxFileBytes,
          maxCaptureBytes,
          includeHiddenDirectories,
        ),
      );
    } on FileSystemException {
      throw KnowledgeFailure(
        KnowledgeFailureCode.denied,
        'open',
        'The granted project directory is unavailable.',
      );
    }
  }
}

final class _LocalSource {
  _LocalSource(
    this._root,
    this.bundleIds,
    this.maxFileBytes,
    this.maxCaptureBytes,
    this.includeHiddenDirectories,
  );
  final String _root;
  final Map<String, String> bundleIds;
  final int maxFileBytes;
  final int maxCaptureBytes;
  final bool includeHiddenDirectories;
  KnowledgeCapture? _previous;
  Future<KnowledgeCapture> capture() async {
    try {
      if (await FileSystemEntity.type(_root, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.notFound,
          'refresh',
          'The granted project directory no longer exists.',
        );
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final first = await _scan();
        // A matching full byte scan needs neither another scan nor projection.
        // No mtime/size heuristic can hide same-length edits.
        if (_previous?.manifestFingerprint == first.byteFingerprint) {
          return _previous!;
        }
        final second = await _scan();
        if (first.byteFingerprint != second.byteFingerprint) continue;
        return _previous = KnowledgeCapture(
          files: first.files,
          bundles: [
            for (final bundle in first.bundles)
              projectCapturedBundle(
                id: bundle.id,
                path: bundle.path,
                files: first.files.where((f) => f.bundle == bundle.id).toList(),
              ),
          ],
        );
      }
      throw KnowledgeFailure(
        KnowledgeFailureCode.sourceChanged,
        'refresh',
        'Source files changed during capture; refresh again.',
      );
    } on FileSystemException {
      throw KnowledgeFailure(
        KnowledgeFailureCode.unavailable,
        'refresh',
        'A source file became unreadable during capture.',
      );
    } on WayfinderConfigException {
      throw KnowledgeFailure(
        KnowledgeFailureCode.invalidContent,
        'refresh',
        'Project configuration is invalid.',
        path: 'wayfinder.json',
      );
    }
  }

  Future<_Scan> _scan() async {
    final files = <KnowledgeCapturedFile>[];
    var total = 0;
    Future<void> add(
      String projectPath,
      String? bundle,
      String relative,
    ) async {
      _relativePath(projectPath);
      await _regular(projectPath);
      final file = File(p.join(_root, projectPath));
      final stat = await file.stat();
      if (stat.size > maxFileBytes || stat.size > maxCaptureBytes - total) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.tooLarge,
          'capture',
          'Source capture exceeds its configured byte limit.',
          path: projectPath,
        );
      }
      // Read at most the bound even if a writer grows a file after stat.
      final remaining = maxCaptureBytes - total;
      final limit = remaining < maxFileBytes ? remaining : maxFileBytes;
      final reader = await file.open();
      late final List<int> bytes;
      try {
        bytes = await reader.read(limit + 1);
      } finally {
        await reader.close();
      }
      if (bytes.length > limit) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.tooLarge,
          'capture',
          'Source capture exceeds its configured byte limit.',
          path: projectPath,
        );
      }
      await _regular(projectPath);
      total += bytes.length;
      files.add(
        KnowledgeCapturedFile(
          bundle: bundle,
          path: relative,
          bytes: bytes,
          mediaType: _media(relative),
        ),
      );
    }

    var paths = <String>[];
    final configType = await _type('wayfinder.json');
    if (configType != FileSystemEntityType.notFound) {
      await add('wayfinder.json', null, 'wayfinder.json');
      try {
        paths = WayfinderProjectConfig.parse(
          utf8.decode(files.last.bytes),
        ).bundles.map((b) => b.path).toList();
      } on FormatException {
        throw KnowledgeFailure(
          KnowledgeFailureCode.invalidContent,
          'discovery',
          'Project configuration is not valid UTF-8 JSON.',
          path: 'wayfinder.json',
        );
      }
    } else if (await _type('knowledge') == FileSystemEntityType.directory) {
      paths = ['knowledge'];
    }
    // An existing project with no discovered bundle is an empty success.
    if (await _type('wayfinder.lock') != FileSystemEntityType.notFound) {
      await add('wayfinder.lock', null, 'wayfinder.lock');
    }
    paths.sort();
    final bundles = <({String id, String path})>[];
    for (final path in paths) {
      _relativePath(path);
      await _directory(path);
      final bundleId =
          bundleIds[path] ??
          'local:${sha256.convert(utf8.encode(_root)).toString()}:$path';
      bundles.add((id: bundleId, path: path));
      Future<void> visit(String relative) async {
        final projectPath = relative.isEmpty ? path : '$path/$relative';
        await _directory(projectPath);
        final children = await Directory(
          p.join(_root, projectPath),
        ).list(followLinks: false).toList();
        children.sort((a, b) => a.path.compareTo(b.path));
        for (final child in children) {
          final name = p.basename(child.path);
          final childRelative = relative.isEmpty ? name : '$relative/$name';
          // The root coordination lock is outside the browsing inventory.
          if (childRelative == '.okf.lock') continue;
          final kind = await _type('$path/$childRelative');
          if (kind == FileSystemEntityType.directory) {
            if (!includeHiddenDirectories && name.startsWith('.')) {
              continue;
            }
            await visit(childRelative);
          } else if (kind == FileSystemEntityType.file) {
            await add('$path/$childRelative', bundleId, childRelative);
          }
          // Symlinks and nonregular devices are outside the granted inventory.
        }
      }

      await visit('');
    }
    return _Scan(files, bundles);
  }

  Future<FileSystemEntityType> _type(String relative) async {
    _relativePath(relative);
    var current = _root;
    final segments = relative.split('/');
    for (var i = 0; i < segments.length; i++) {
      current = p.join(current, segments[i]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        // The inventory excludes links; direct traversal/config access refuses.
        if (i == segments.length - 1) return type;
        throw KnowledgeFailure(
          KnowledgeFailureCode.denied,
          'access',
          'Source paths may not traverse symbolic links.',
          path: relative,
        );
      }
      if (i == segments.length - 1) return type;
      if (type != FileSystemEntityType.directory) {
        return FileSystemEntityType.notFound;
      }
    }
    return FileSystemEntityType.notFound;
  }

  Future<void> _regular(String path) async {
    final type = await _type(path);
    if (type != FileSystemEntityType.file) {
      throw KnowledgeFailure(
        type == FileSystemEntityType.link
            ? KnowledgeFailureCode.denied
            : KnowledgeFailureCode.unavailable,
        'read',
        'Only granted regular files can be read.',
        path: path,
      );
    }
    final canonical = await File(p.join(_root, path)).resolveSymbolicLinks();
    if (!p.isWithin(_root, canonical) ||
        !p.equals(canonical, p.join(_root, path))) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.denied,
        'read',
        'The file is outside the granted source path.',
        path: path,
      );
    }
  }

  Future<void> _directory(String path) async {
    final type = await _type(path);
    if (type != FileSystemEntityType.directory) {
      throw KnowledgeFailure(
        type == FileSystemEntityType.link
            ? KnowledgeFailureCode.denied
            : KnowledgeFailureCode.notFound,
        'inventory',
        'The bundle directory is unavailable or symbolic.',
        path: path,
      );
    }
    final canonical = await Directory(
      p.join(_root, path),
    ).resolveSymbolicLinks();
    if (!p.isWithin(_root, canonical) ||
        !p.equals(canonical, p.join(_root, path))) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.denied,
        'inventory',
        'The directory is outside the granted source path.',
        path: path,
      );
    }
  }
}

final class _Scan {
  _Scan(this.files, this.bundles);
  final List<KnowledgeCapturedFile> files;
  final List<({String id, String path})> bundles;
  late final String byteFingerprint = knowledgeManifestFingerprint(
    files: [for (final f in files) (f.bundle, f.path, f.digest)],
    bundles: [for (final b in bundles) (b.id, b.path)],
  );
}

String? _media(String path) => switch (p.posix.extension(path).toLowerCase()) {
  '.md' => 'text/markdown',
  '.json' => 'application/json',
  '.txt' => 'text/plain',
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.pdf' => 'application/pdf',
  _ => null,
};

void _relativePath(String path) {
  try {
    knowledgeRelativePath(path);
  } on ArgumentError {
    throw KnowledgeFailure(
      KnowledgeFailureCode.invalidContent,
      'capture',
      'The source path cannot be represented as a portable relative address.',
      path: path,
    );
  }
}
