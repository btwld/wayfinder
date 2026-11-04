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
      for (var i = 0; i < 257; i++)
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

  test(
    'an encoder failure after a flush preserves only the earlier batch',
    () async {
      final store = MemoryStore();
      addTearDown(store.close);
      final pipeline = IngestionPipeline(
        chunkerRegistry: ChunkerRegistry(),
        embedder: _FailSecondBatch(),
        store: store,
      );
      final many = [
        for (var i = 0; i < 257; i++)
          Chunk(
            id: 'c$i',
            sourcePath: 'one.txt',
            lineStart: i + 1,
            lineEnd: i + 1,
            content: 'Line $i',
            type: 'text',
          ),
      ];
      await expectLater(
        pipeline.ingest([
          (file: File('one.txt'), chunks: many),
          (
            file: File('two.txt'),
            chunks: [many.first.copyWith(id: 'new', content: 'New')],
          ),
        ]),
        throwsStateError,
      );
      expect((await store.getAllChunks()).length, 257);
      expect((await store.getAllEmbeddings()).length, 257);
    },
  );

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
        embedder: _Encoder(),
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
    skip:
        !File('/usr/local/lib/libobjectbox.so').existsSync() &&
            !File('lib/libobjectbox.so').existsSync() &&
            Platform.environment['WAYFINDER_REQUIRE_NATIVE'] != '1'
        ? 'ObjectBox native library unavailable'
        : false,
  );
}

class _Encoder extends BaseEmbedder {
  @override
  String get sourceName => 'test';
  @override
  String get modelName => 'fixed';
  @override
  int get dimension => 384;
  @override
  Future<List<double>> generateEmbedding(String text) async => [
    1,
    ...List.filled(383, 0.0),
  ];
}

class _FailSecondBatch extends _Encoder {
  int calls = 0;
  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) {
    if (++calls == 2) throw StateError('Encoder failed');
    return super.generateEmbeddings(texts);
  }
}
