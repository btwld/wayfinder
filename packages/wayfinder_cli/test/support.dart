import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> copyBitwildPackage(String repository) async {
  final package = Directory(p.join('..', '..', 'profiles', 'bitwild'));
  await for (final entity in package.list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(
      p.join(
        repository,
        'profiles',
        'bitwild',
        p.relative(entity.path, from: package.path),
      ),
    );
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

/// Deterministic 384-dimension vectors keyed on two words, for test encoders.
/// They exercise storage, ranking and output; they are not retrieval-quality
/// evidence.
List<double> keywordVector(String text) => [
  text.toLowerCase().contains('password') ? 1 : 0,
  text.toLowerCase().contains('weather') || text.contains('Rain') ? 1 : 0,
  0.01,
  ...List.filled(381, 0.0),
];

/// Skips tests that index or search for real when the ObjectBox library
/// `melos run objectbox:install` puts in `wayfinder_embeddings/lib` is absent.
Object? get skipWithoutObjectBox =>
    File(
      p.join(
        '..',
        'wayfinder_embeddings',
        'lib',
        Platform.isMacOS
            ? 'libobjectbox.dylib'
            : Platform.isWindows
            ? 'objectbox.dll'
            : 'libobjectbox.so',
      ),
    ).existsSync()
    ? false
    : 'Install ObjectBox to run persistence tests.';
