// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic fixture handling.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'support/chunk_manifest.dart';

void main() {
  test('sample chunk manifest matches the golden snapshot', () {
    expectChunkGolden(
      registry: defaultCodeRegistry(),
      fixturesDir: Directory('fixtures/samples'),
      golden: File('test/goldens/sample_chunks.json'),
    );
  });

  test('sample chunk ids do not depend on the checkout root', () {
    final fixturesDir = Directory('fixtures/samples').absolute;
    final rebasedDir = Directory(
      p.join(Directory.systemTemp.path, 'other-checkout'),
    );
    final chunker = DartChunker();
    final original = <Chunk>[];
    final rebased = <Chunk>[];
    for (final file in collectFixtureFiles(fixturesDir)) {
      final content = file.readAsStringSync();
      final metadata = ChunkMetadata.fromFile(file);
      original.addAll(chunker.chunkContent(content, metadata));
      rebased.addAll(
        chunker.chunkContent(
          content,
          metadata.copyWith(
            sourcePath: p.join(
              rebasedDir.path,
              p.relative(file.path, from: fixturesDir.path),
            ),
          ),
        ),
      );
    }
    expect(original, isNotEmpty);
    expect(
      buildChunkManifest(rebased, rebasedDir),
      buildChunkManifest(original, fixturesDir),
    );
  });
}
