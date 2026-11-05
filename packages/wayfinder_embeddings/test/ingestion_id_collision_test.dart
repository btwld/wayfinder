import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  for (final acrossFiles in [false, true]) {
    test(
      'refuses conflicting id text within one ingest (across files: $acrossFiles)',
      () async {
        final store = MemoryStore();
        addTearDown(store.close);
        final first = Chunk(
          id: 'explicit',
          sourcePath: 'one.txt',
          lineStart: 1,
          lineEnd: 1,
          content: 'Original',
          type: 'text',
        );
        final conflict = first.copyWith(id: first.id, content: 'Different');
        final pipeline = IngestionPipeline(
          chunkerRegistry: ChunkerRegistry(),
          embedder: _Encoder(),
          store: store,
        );
        await expectLater(
          pipeline.ingest([
            (
              file: File('one.txt'),
              chunks: [first, if (!acrossFiles) conflict],
            ),
            if (acrossFiles) (file: File('two.txt'), chunks: [conflict]),
          ]),
          throwsStateError,
        );
        expect(await store.getAllChunks(), isEmpty);
        expect(await store.getAllEmbeddings(), isEmpty);
      },
    );
  }
}

class _Encoder extends BaseEmbedder {
  @override
  String get sourceName => 'test';
  @override
  String get modelName => 'fixed';
  @override
  int get dimension => 2;
  @override
  Future<List<double>> generateEmbedding(String text) async => [1, 0];
}
