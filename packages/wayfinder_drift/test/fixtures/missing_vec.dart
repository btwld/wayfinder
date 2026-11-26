import 'dart:io';

import 'package:wayfinder/project.dart';
import 'package:wayfinder_drift/wayfinder_drift.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

Future<void> main(List<String> args) async {
  final [generationPath, dataPath, bundleRoot] = args;
  const format = SqliteGenerationFormat();
  try {
    final reader = await format.open(Directory(generationPath));
    await reader.close();
    throw StateError('The index opened without the sqlite-vec native asset.');
  } on GenerationOpenException catch (error) {
    stdout.writeln('open: ${error.message}');
  }

  final store = WayfinderKnowledgeStore(
    dataDirectory: Directory(dataPath),
    encoder: TestEncoderProvider(
      [],
      beforeOpen: () async => throw StateError('Migration opened an encoder.'),
    ),
    formats: [format],
  );
  try {
    await store.index(ProjectBundle('knowledge', 'knowledge', bundleRoot));
    throw StateError('The index was published without the sqlite-vec asset.');
  } on WayfinderException catch (error) {
    stdout.writeln('write: ${error.code}: ${error.message}');
  } finally {
    await store.dispose();
  }
}
