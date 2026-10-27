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

  test('refuses conflicting id text after >256 chunks without partial writes '
      'and preserves metadata updates on duplicate ids', () async {
    final store = MemoryStore();
    addTearDown(store.close);
    final pipeline = IngestionPipeline(
      chunkerRegistry: ChunkerRegistry(),
      embedder: _Encoder(),
      store: store,
    );
    final many = [
      for (var i = 0; i < 150; i++)
        Chunk(
          id: 'c$i',
          sourcePath: 'one.txt',
          lineStart: i + 1,
          lineEnd: i + 1,
          content: 'Line $i',
          type: 'text',
        ),
    ];
    final conflict = many.first.copyWith(id: 'c0', content: 'Different');
    await expectLater(
      pipeline.ingest([
        (file: File('one.txt'), chunks: many),
        (file: File('two.txt'), chunks: [conflict]),
      ]),
      throwsStateError,
    );
    expect(await store.getAllChunks(), isEmpty);
    expect(await store.getAllEmbeddings(), isEmpty);

    final first = Chunk(
      id: 'same',
      sourcePath: 'one.txt',
      lineStart: 1,
      lineEnd: 1,
      content: 'Same text',
      type: 'text',
      metadata: const {'v': 1},
    );
    final updated = first.copyWith(
      id: 'same',
      lineStart: 5,
      lineEnd: 5,
      metadata: const {'v': 2},
    );
    await pipeline.ingest([
      (file: File('one.txt'), chunks: [first, updated]),
    ]);
    final stored = (await store.getAllChunks()).single;
    expect(stored.lineStart, 5);
    expect(stored.metadata, const {'v': 2});
  });
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
