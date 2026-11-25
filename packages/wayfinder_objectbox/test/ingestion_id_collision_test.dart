import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/testing.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

void main() {
  test(
    'ObjectBox stores one final metadata value per duplicate id',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ingestion-objectbox-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final store = ObjectBoxStore.open('${temp.path}/db');
      addTearDown(store.close);
      final chunk = Chunk(
        id: 'same',
        sourcePath: 'one.txt',
        lineStart: 1,
        lineEnd: 1,
        content: 'Unchanged',
        type: 'text',
        metadata: const {'v': 1},
      );
      await IngestionPipeline(
        chunkerRegistry: ChunkerRegistry(),
        embedder: DeterministicTestEmbedder(),
        store: store,
      ).ingest([
        (
          file: File('one.txt'),
          chunks: [
            chunk,
            chunk.copyWith(metadata: const {'v': 2}),
          ],
        ),
      ]);
      expect((await store.getAllChunks()).single.metadata, const {'v': 2});
      expect(await store.getAllEmbeddings(), hasLength(1));
    },
    tags: ['native'],
    skip: Platform.environment['WAYFINDER_REQUIRE_NATIVE'] != '1',
  );
}
