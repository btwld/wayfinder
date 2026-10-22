import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config_search.dart';

/// The project files a write's Profile selection came from, which
/// `KnowledgeWriter.commit` checks under okf's exclusive bundle lock: each
/// absolute path with the SHA-256 of the bytes it held, or null for a file
/// that was absent.
///
/// For a bundle a `wayfinder.json` binds, they are that file, the
/// `wayfinder.lock` beside it, and each closer `wayfinder.json` path binding
/// looked at first, absent, since a configuration that appears there would
/// bind the bundle instead. For a bundle none binds, they are the
/// `wayfinder.json` paths binding looked at, each absent, so a
/// configuration that appears there, which would select a Profile, makes a
/// plan judged without one stale too.
///
/// A host captures them together with its own selection, before it selects
/// ([forBundle], [read]) or from the bytes it read itself (the default
/// constructor), so a change between its selection and `prepare` is caught
/// as well.
final class KnowledgeProjectFiles {
  /// [sha256] maps each path to the lowercase hexadecimal SHA-256 of the
  /// bytes a host read ([digest]), or to null for a file that was absent.
  ///
  /// Each path is made absolute against the current directory now, and
  /// normalized, so the check at commit reads the files the host meant
  /// wherever the process is then. Throws [ArgumentError] when two paths
  /// name the same file with different digests.
  KnowledgeProjectFiles(Map<String, String?> sha256)
    : sha256 = Map.unmodifiable(_absolute(sha256));

  /// No project file, as for a selection a host built itself: a plan with
  /// them is stale only when its bundle changes.
  static final none = KnowledgeProjectFiles(const {});

  /// `wayfinder.json` at [configPath] and the `wayfinder.lock` beside it,
  /// as they are now.
  static Future<KnowledgeProjectFiles> read(String configPath) async {
    final config = p.normalize(File(configPath).absolute.path);
    return _of([config, p.join(p.dirname(config), 'wayfinder.lock')]);
  }

  /// The files binding [bundle] reads, as they are now, found as
  /// `WayfinderProjectConfig.bind` finds them: [configPath] with the
  /// `wayfinder.lock` beside it; or else each `wayfinder.json` path the
  /// search above the bundle, never above [projectRoot], looked at, closest
  /// first, ending with the one it found and the `wayfinder.lock` beside
  /// it. The paths before the one it found are absent, and one that appears
  /// would bind the bundle instead. Reads no configuration's content.
  static Future<KnowledgeProjectFiles> forBundle(
    String bundle, {
    String? configPath,
    String? projectRoot,
  }) async {
    if (configPath != null) return read(configPath);
    return _of((await _bound(bundle, projectRoot)).paths);
  }

  /// The SHA-256 of [bytes] as [sha256] records it: lowercase hexadecimal.
  static String digest(List<int> bytes) => sha256Of(bytes);

  /// Each tracked absolute path, with the SHA-256 of its bytes or null for
  /// a file that was absent.
  final Map<String, String?> sha256;

  /// The tracked paths whose bytes differ now from [sha256], in its order:
  /// changed, created or deleted. A file that cannot be read counts as
  /// absent.
  Future<List<String>> changed() async => [
    for (final MapEntry(key: path, value: digest) in sha256.entries)
      if (await _digest(path) != digest) path,
  ];

  static Future<KnowledgeProjectFiles> _of(Iterable<String> paths) async =>
      KnowledgeProjectFiles({
        for (final path in paths) path: await _digest(path),
      });

  /// Each `wayfinder.json` path binding [bundle] looks at, closest first,
  /// absolute and normalized, followed by the `wayfinder.lock` beside the
  /// last when the search found it ([found]).
  static Future<({List<String> paths, String? found})> _bound(
    String bundle,
    String? projectRoot,
  ) async {
    final (:found, :searched) = await searchProjectConfig(
      bundle,
      projectRoot: projectRoot,
    );
    final paths = [
      for (final path in searched) p.normalize(File(path).absolute.path),
    ];
    if (found == null) return (paths: paths, found: null);
    final config = paths.last;
    return (
      paths: [...paths, p.join(p.dirname(config), 'wayfinder.lock')],
      found: config,
    );
  }

  static Map<String, String?> _absolute(Map<String, String?> sha256) {
    final absolute = <String, String?>{};
    for (final MapEntry(key: path, value: digest) in sha256.entries) {
      final key = p.normalize(File(path).absolute.path);
      if (absolute.containsKey(key) && absolute[key] != digest) {
        throw ArgumentError.value(
          path,
          'sha256',
          'names $key, which another path gives another digest',
        );
      }
      absolute[key] = digest;
    }
    return absolute;
  }

  static Future<String?> _digest(String path) async {
    try {
      return sha256Of(await File(path).readAsBytes());
    } on FileSystemException {
      return null;
    }
  }
}

/// The project files of a selection of [bundle] that came from the
/// configuration at [configPath]: [KnowledgeProjectFiles.read] of it, and
/// also each closer `wayfinder.json` path, absent, when binding [bundle]
/// within [projectRoot] finds that configuration, since one that appears
/// there would bind the bundle instead. A configuration binding does not
/// find, such as one a host named, is tracked alone with its lock.
Future<KnowledgeProjectFiles> projectFilesOf(
  String bundle,
  String configPath, {
  String? projectRoot,
}) async {
  final config = p.normalize(File(configPath).absolute.path);
  final (:paths, :found) = await KnowledgeProjectFiles._bound(
    bundle,
    projectRoot,
  );
  if (found != null && p.equals(found, config)) {
    return KnowledgeProjectFiles._of(paths);
  }
  return KnowledgeProjectFiles.read(config);
}

/// The lowercase hexadecimal SHA-256 of [bytes].
String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();
