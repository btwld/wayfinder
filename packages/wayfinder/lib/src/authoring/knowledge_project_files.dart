import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config_search.dart';

/// The project files a write's Profile selection came from, which
/// `KnowledgeWriter.commit` checks under okf's exclusive bundle lock: each
/// absolute path with the SHA-256 of the bytes it held, or null for a file
/// that was absent.
///
/// For a bundle a `wayfinder.json` binds, they are that file and the
/// `wayfinder.lock` beside it. For a bundle none binds, they are the
/// `wayfinder.json` paths binding looked at, each absent, so a
/// configuration that appears there, which would select a Profile, makes a
/// plan judged without one stale too.
///
/// A host captures them together with its own selection, before it selects
/// ([forBundle], [read]) or from the bytes it read itself (the default
/// constructor), so a change between its selection and `prepare` is caught
/// as well.
final class KnowledgeProjectFiles {
  /// [sha256] maps each absolute path to the lowercase hexadecimal SHA-256
  /// of the bytes a host read ([digest]), or to null for a file that was
  /// absent.
  KnowledgeProjectFiles(Map<String, String?> sha256)
    : sha256 = Map.unmodifiable(sha256);

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
  /// `WayfinderProjectConfig.bind` finds them: [configPath], or the nearest
  /// `wayfinder.json` above the bundle, never above [projectRoot], with the
  /// `wayfinder.lock` beside it; or, when no `wayfinder.json` is found, each
  /// path the search looked at, absent. Reads no configuration's content.
  static Future<KnowledgeProjectFiles> forBundle(
    String bundle, {
    String? configPath,
    String? projectRoot,
  }) async {
    if (configPath != null) return read(configPath);
    final (:found, :searched) = await searchProjectConfig(
      bundle,
      projectRoot: projectRoot,
    );
    if (found != null) return read(found.path);
    return _of([for (final path in searched) p.normalize(path)]);
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

  static Future<String?> _digest(String path) async {
    try {
      return sha256Of(await File(path).readAsBytes());
    } on FileSystemException {
      return null;
    }
  }
}

/// The lowercase hexadecimal SHA-256 of [bytes].
String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();
