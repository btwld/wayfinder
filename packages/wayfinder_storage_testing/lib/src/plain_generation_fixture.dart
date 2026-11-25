import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:wayfinder_embeddings/knowledge_store.dart';

/// Installs the frozen plain-file fixture in [generation] for [bundleRoot].
///
/// Replaces the existing files of a plain generation. Returns the recorded
/// public search result for the query `password recovery`.
Future<Map<String, Object?>> installPlainGenerationFixture(
  Directory generation,
  String bundleRoot,
) async {
  final library = (await Isolate.resolvePackageUri(
    Uri.parse(
      'package:wayfinder_storage_testing/wayfinder_storage_testing.dart',
    ),
  ))!;
  final fixture = library.resolve('../test/fixtures/plain-generation/');
  final root = jsonEncode(bundleRoot);
  Future<String> text(String name) async =>
      (await File.fromUri(fixture.resolve(name)).readAsString()).replaceAll(
        '@BUNDLE_ROOT@',
        root.substring(1, root.length - 1),
      );

  await File.fromUri(
    generation.uri.resolve(IndexGeneration.snapshotFile),
  ).writeAsString(await text('snapshot.json'), flush: true);
  await File.fromUri(fixture.resolve(IndexGeneration.vectorsFile)).copy(
    File.fromUri(generation.uri.resolve(IndexGeneration.vectorsFile)).path,
  );
  return jsonDecode(await text('search.json')) as Map<String, Object?>;
}
