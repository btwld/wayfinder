// ignore_for_file: avoid_slow_async_io
// The writer runs once by hand; sync file checks keep it short.

/// The synthetic data in `test/fixtures/objectbox-0.2.0/`, and the program
/// that wrote it with `wayfinder_embeddings` 0.2.0.
///
/// The fixture's README says how to run [main] against that release. The
/// test imports [fixtureChunks] and [fixtureEmbeddings] to check what a
/// current store reads back. The data is synthetic.
library;

import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// The model name every fixture embedding uses, except the second identity.
const fixtureModelName = 'fixture-model';

/// The embedding source every fixture embedding uses.
const fixtureSource = 'dense';

/// A second model identity stored beside the first for one chunk.
const fixtureOtherModelName = 'fixture-model-b';

/// A 384-dimensional vector whose values are exact in float32.
List<double> fixtureVector(int seed) {
  final vector = List<double>.filled(384, 0);
  final base = (seed * 7) % 384;
  vector[base] = 1;
  vector[(base + 1) % 384] = -0.5;
  vector[(base + 2) % 384] = 0.25;
  return vector;
}

/// The chunks, in the order they were written.
final List<Chunk> fixtureChunks = [
  Chunk(
    sourcePath: 'knowledge/guidance/retries.md',
    lineStart: 5,
    lineEnd: 9,
    content: 'Retry a failed delivery at most three times, then quarantine it.',
    type: 'paragraph',
    metadata: {
      'headingPath': ['Retries', 'Limits'],
      'status': 'current',
    },
  ),
  Chunk(
    sourcePath: 'knowledge/guidance/retries.md',
    lineStart: 1,
    lineEnd: 1,
    content: '# Retries',
    type: 'heading',
    metadata: {'level': 1},
  ),
  Chunk(
    sourcePath: 'knowledge/history/rotation.md',
    lineStart: 3,
    lineEnd: 4,
    content: 'Keys rotated every ninety days until the policy changed.',
    type: 'paragraph',
    metadata: {'status': 'historical', 'tags': <String>[]},
  ),
  Chunk(
    sourcePath: 'lib/service.ts',
    lineStart: 10,
    lineEnd: 24,
    content: 'export class Service {\n  start(): void {}\n}',
    type: 'class',
    metadata: {'name': 'Service', 'exported': true},
  ),
];

/// The embeddings, in the order they were written.
final List<Embedding> fixtureEmbeddings = [
  for (var index = 0; index < fixtureChunks.length; index++)
    Embedding(
      chunkId: fixtureChunks[index].id,
      source: fixtureSource,
      modelName: fixtureModelName,
      vector: fixtureVector(index + 1),
    ),
  Embedding(
    chunkId: fixtureChunks.first.id,
    source: fixtureSource,
    modelName: fixtureOtherModelName,
    vector: fixtureVector(40),
  ),
];

/// Writes the fixture store into the empty directory `args.single`.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: objectbox_0_2_0_fixture.dart OUTPUT_DIRECTORY');
    exitCode = 64;
    return;
  }
  final output = Directory(args.single);
  if (output.existsSync() && output.listSync().isNotEmpty) {
    stderr.writeln('Output directory must be empty: ${output.path}');
    exitCode = 1;
    return;
  }
  final store = ObjectBoxStore.open(output.path);
  try {
    await store.storeBatch(
      chunks: fixtureChunks,
      embeddings: fixtureEmbeddings,
    );
  } finally {
    await store.close();
  }
  stdout.writeln('Wrote the ObjectBox fixture to ${output.path}');
}
