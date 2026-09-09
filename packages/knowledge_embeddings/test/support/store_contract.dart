import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/src/storage/embedding_entities.dart';
import 'package:test/test.dart';

/// Creates a 384-dimensional test vector with a unique pattern based on seed.
List<double> testVector384({int seed = 0}) {
  final vector = List<double>.filled(objectBoxEmbeddingDimension, 0.0);
  vector[seed % objectBoxEmbeddingDimension] = 1.0;
  if (seed > 0) {
    vector[(seed + 1) % objectBoxEmbeddingDimension] = 0.5;
  }
  return vector;
}

/// Registers the behavior every [BaseStore] implementation must provide.
///
/// [createStore] builds a fresh store for each test.
void runStoreContract(BaseStore Function() createStore) {
  late BaseStore store;

  setUp(() {
    store = createStore();
  });

  tearDown(() async {
    await store.close();
  });

  test(
    'replacement removes obsolete vectors and preserves unrelated chunks',
    () async {
      Chunk chunk(String name) => Chunk(
        sourcePath: '$name.md',
        lineStart: 1,
        lineEnd: 1,
        content: name,
        type: 'text',
      );
      final old = chunk('old');
      final unrelated = chunk('unrelated');
      final replacement = chunk('replacement');
      Embedding vector(Chunk chunk, String model) => Embedding(
        chunkId: chunk.id,
        source: 'dense',
        modelName: model,
        vector: testVector384(),
      );
      await store.storeBatch(
        chunks: [old, unrelated],
        embeddings: [
          vector(old, 'a'),
          vector(old, 'b'),
          vector(unrelated, 'a'),
        ],
      );
      await expectLater(
        store.replaceChunks(
          chunks: [],
          embeddings: [vector(old, 'a')],
          removeChunkIds: {old.id},
        ),
        throwsArgumentError,
      );
      expect(await store.getChunk(old.id), old);
      expect(await store.getAllEmbeddings(), hasLength(3));
      await store.replaceChunks(
        chunks: [replacement],
        embeddings: [vector(replacement, 'a')],
        removeChunkIds: {old.id},
      );
      expect(await store.getChunk(old.id), isNull);
      expect(await store.getChunk(unrelated.id), unrelated);
      expect(await store.getChunk(replacement.id), replacement);
      expect(
        (await store.getAllEmbeddings()).map((item) => item.chunkId),
        unorderedEquals([unrelated.id, replacement.id]),
      );
    },
  );

  test(
    'eligible vector lookup enforces chunk, source, and model together',
    () async {
      final chunks = [
        for (var i = 0; i < 81; i++)
          Chunk(
            sourcePath: '$i.md',
            lineStart: 1,
            lineEnd: 1,
            content: 'item $i',
            type: 'text',
          ),
      ];
      Embedding vector(Chunk chunk, String source, String model) => Embedding(
        chunkId: chunk.id,
        source: source,
        modelName: model,
        vector: testVector384(),
      );
      final target = vector(chunks.last, 'dense', 'current');
      await store.storeBatch(
        chunks: chunks,
        embeddings: [
          for (final chunk in chunks) vector(chunk, 'dense', 'old'),
          vector(chunks.last, 'other', 'current'),
          target,
        ],
      );
      expect(
        await store.getEmbeddingsForChunks(
          {chunks.last.id},
          source: 'dense',
          modelName: 'current',
        ),
        [target],
      );
      expect(
        await store.getEmbeddingsForChunks(
          {},
          source: 'dense',
          modelName: 'current',
        ),
        isEmpty,
      );
      expect(
        await store.getEmbeddingsForChunks(
          {chunks.first.id},
          source: 'dense',
          modelName: 'current',
        ),
        isEmpty,
      );
    },
  );

  test('stores and retrieves chunks and embeddings', () async {
    final chunk = Chunk(
      sourcePath: 'lib/example.dart',
      lineStart: 1,
      lineEnd: 5,
      content: 'void main() {}',
      type: 'function',
      metadata: {'language': 'dart'},
    );
    final embedding = Embedding(
      chunkId: chunk.id,
      source: 'test',
      modelName: 'model',
      vector: testVector384(seed: 1),
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(embedding);

    expect(await store.getChunk(chunk.id), equals(chunk));
    expect(await store.getEmbedding(chunk.id), equals(embedding));
  });

  test(
    'retrieves embeddings by source and model when multiple exist',
    () async {
      final chunk = Chunk(
        sourcePath: 'lib/example.dart',
        lineStart: 1,
        lineEnd: 5,
        content: 'void main() {}',
        type: 'function',
      );
      final denseEmbedding = Embedding(
        chunkId: chunk.id,
        source: 'dense',
        modelName: 'model-a',
        vector: testVector384(seed: 1),
      );
      final lexicalEmbedding = Embedding(
        chunkId: chunk.id,
        source: 'local',
        modelName: 'local-bm25',
        vector: testVector384(seed: 2),
      );

      await store.storeChunk(chunk);
      await store.storeEmbedding(denseEmbedding);
      await store.storeEmbedding(lexicalEmbedding);

      expect(
        await store.getEmbedding(
          chunk.id,
          source: 'local',
          modelName: 'local-bm25',
        ),
        equals(lexicalEmbedding),
      );
      expect(await store.getEmbedding(chunk.id, source: 'missing'), isNull);
      expect(await store.getAllEmbeddings(), hasLength(2));
    },
  );

  test('stores embeddings whose identity parts contain delimiters', () async {
    final firstChunk = Chunk(
      id: 'chunk::alpha',
      sourcePath: 'first.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'first',
      type: 'text',
    );
    final secondChunk = Chunk(
      id: 'chunk',
      sourcePath: 'second.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'second',
      type: 'text',
    );
    final firstEmbedding = Embedding(
      chunkId: firstChunk.id,
      source: 'source',
      modelName: 'model',
      vector: testVector384(seed: 1),
    );
    final secondEmbedding = Embedding(
      chunkId: secondChunk.id,
      source: 'alpha::source',
      modelName: 'model',
      vector: testVector384(seed: 2),
    );

    await store.storeChunk(firstChunk);
    await store.storeChunk(secondChunk);
    await store.storeEmbedding(firstEmbedding);
    await store.storeEmbedding(secondEmbedding);

    expect(await store.getAllEmbeddings(), hasLength(2));
    expect(
      await store.getEmbedding(
        firstChunk.id,
        source: firstEmbedding.source,
        modelName: firstEmbedding.modelName,
      ),
      firstEmbedding,
    );
    expect(
      await store.getEmbedding(
        secondChunk.id,
        source: secondEmbedding.source,
        modelName: secondEmbedding.modelName,
      ),
      secondEmbedding,
    );
  });

  test('findSimilar orders results by similarity', () async {
    final chunkA = Chunk(
      sourcePath: 'a.dart',
      lineStart: 1,
      lineEnd: 2,
      content: 'a',
      type: 'function',
    );
    final chunkB = Chunk(
      sourcePath: 'b.dart',
      lineStart: 1,
      lineEnd: 2,
      content: 'b',
      type: 'function',
    );

    await store.storeChunk(chunkA);
    await store.storeChunk(chunkB);

    await store.storeEmbedding(
      Embedding(
        chunkId: chunkA.id,
        source: 'bm25',
        modelName: 'local',
        vector: testVector384(seed: 1),
      ),
    );
    await store.storeEmbedding(
      Embedding(
        chunkId: chunkB.id,
        source: 'bm25',
        modelName: 'local',
        vector: testVector384(seed: 2),
      ),
    );

    final results = await store.findSimilar(
      testVector384(seed: 1),
      'bm25',
      'local',
    );
    expect(results, hasLength(2));
    expect(results.first.chunk.id, chunkA.id);
    expect(results.first.similarity, greaterThan(results.last.similarity));
  });

  test('findSimilar orders equal scores deterministically', () async {
    final chunkZ = Chunk(
      sourcePath: 'z.dart',
      lineStart: 1,
      lineEnd: 2,
      content: 'z',
      type: 'function',
    );
    final chunkA = Chunk(
      sourcePath: 'a.dart',
      lineStart: 1,
      lineEnd: 2,
      content: 'a',
      type: 'function',
    );

    await store.storeChunk(chunkZ);
    await store.storeChunk(chunkA);

    for (final chunk in [chunkZ, chunkA]) {
      await store.storeEmbedding(
        Embedding(
          chunkId: chunk.id,
          source: 'dense',
          modelName: 'model',
          vector: testVector384(seed: 1),
        ),
      );
    }

    final results = await store.findSimilar(
      testVector384(seed: 1),
      'dense',
      'model',
    );

    expect(results.map((result) => result.chunk.sourcePath), [
      'a.dart',
      'z.dart',
    ]);
  });

  test('findSimilar returns empty results for non-positive limits', () async {
    final chunk = Chunk(
      sourcePath: 'limit.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'limit',
      type: 'text',
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(
      Embedding(
        chunkId: chunk.id,
        source: 'bm25',
        modelName: 'local',
        vector: testVector384(seed: 5),
      ),
    );

    expect(
      await store.findSimilar(
        testVector384(seed: 5),
        'bm25',
        'local',
        limit: 0,
      ),
      isEmpty,
    );
    expect(
      await store.findSimilar(
        testVector384(seed: 5),
        'bm25',
        'local',
        limit: -1,
      ),
      isEmpty,
    );
  });

  test('findSimilar rejects invalid query vectors', () async {
    final chunk = Chunk(
      sourcePath: 'query_vector.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'query vector',
      type: 'text',
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(
      Embedding(
        chunkId: chunk.id,
        source: 'dense',
        modelName: 'model',
        vector: testVector384(seed: 1),
      ),
    );

    await expectLater(
      store.findSimilar(const [], 'dense', 'model'),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'queryVector',
        ),
      ),
    );

    final nonFinite = testVector384(seed: 1);
    nonFinite[1] = double.nan;

    await expectLater(
      store.findSimilar(nonFinite, 'dense', 'model'),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'queryVector[1]',
        ),
      ),
    );
  });

  test('rejects blank embedding identity filters', () async {
    final chunk = Chunk(
      sourcePath: 'identity_filter.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'identity filter',
      type: 'text',
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(
      Embedding(
        chunkId: chunk.id,
        source: 'dense',
        modelName: 'model',
        vector: testVector384(seed: 1),
      ),
    );

    await expectLater(
      store.getEmbedding(chunk.id, source: ' '),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'source'),
      ),
    );
    await expectLater(
      store.getEmbedding(chunk.id, modelName: '\t'),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'modelName'),
      ),
    );
    await expectLater(
      store.findSimilar(testVector384(seed: 1), ' ', 'model'),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'source'),
      ),
    );
    await expectLater(
      store.findSimilar(testVector384(seed: 1), 'dense', '\n'),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'modelName'),
      ),
    );
  });

  test('rejects blank chunk identity lookups and deletes', () async {
    await expectLater(
      store.getChunk(' '),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'chunkId'),
      ),
    );
    await expectLater(
      store.getEmbedding('\t'),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'chunkId'),
      ),
    );
    await expectLater(
      store.deleteEmbedding('\n'),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'chunkId'),
      ),
    );
    await expectLater(
      store.deleteChunk(' '),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'chunkId'),
      ),
    );
  });

  test('delete removes stored entities', () async {
    final chunk = Chunk(
      sourcePath: 'lib/foo.dart',
      lineStart: 1,
      lineEnd: 2,
      content: 'foo',
      type: 'function',
    );
    final embedding = Embedding(
      chunkId: chunk.id,
      source: 'bm25',
      modelName: 'local',
      vector: testVector384(seed: 3),
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(embedding);

    await store.deleteEmbedding(chunk.id);
    await store.deleteChunk(chunk.id);

    expect(await store.getChunk(chunk.id), isNull);
    expect(await store.getEmbedding(chunk.id), isNull);
  });

  test(
    'deleting a chunk removes every model while retaining its successor',
    () async {
      final original = Chunk(
        sourcePath: 'guidance.md',
        lineStart: 1,
        lineEnd: 1,
        content: 'Original guidance',
        type: 'paragraph',
      );
      final successor = original.copyWith(content: 'Revised guidance');
      await store.storeBatch(
        chunks: [original, successor],
        embeddings: [
          for (final chunk in [original, successor])
            for (final model in ['old-model', 'new-model'])
              Embedding(
                chunkId: chunk.id,
                source: 'dense',
                modelName: model,
                vector: testVector384(),
              ),
        ],
      );
      await store.deleteChunk(original.id);
      expect(await store.getAllChunks(), [successor]);
      expect((await store.getAllEmbeddings()).map((item) => item.chunkId), [
        successor.id,
        successor.id,
      ]);
      for (final model in ['old-model', 'new-model']) {
        expect(
          (await store.findSimilar(
            testVector384(),
            'dense',
            model,
          )).map((hit) => hit.chunk.id),
          [successor.id],
        );
      }
    },
  );

  test('getStats reports counts', () async {
    final chunk = Chunk(
      sourcePath: 'stats.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'stats',
      type: 'text',
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(
      Embedding(
        chunkId: chunk.id,
        source: 'bm25',
        modelName: 'local',
        vector: testVector384(seed: 4),
      ),
    );

    final stats = await store.getStats();
    expect(stats['chunks'], 1);
    expect(stats['embeddings'], 1);
  });

  test('returns immutable chunk and embedding snapshots', () async {
    final chunk = Chunk(
      sourcePath: 'snapshots.dart',
      lineStart: 1,
      lineEnd: 1,
      content: 'snapshot',
      type: 'text',
    );
    final embedding = Embedding(
      chunkId: chunk.id,
      source: 'dense',
      modelName: 'model',
      vector: testVector384(seed: 6),
    );

    await store.storeChunk(chunk);
    await store.storeEmbedding(embedding);

    final chunks = await store.getAllChunks();
    final embeddings = await store.getAllEmbeddings();

    expect(() => chunks.add(chunk), throwsUnsupportedError);
    expect(
      () => chunks[0] = chunk.copyWith(content: 'changed'),
      throwsUnsupportedError,
    );
    expect(() => embeddings.add(embedding), throwsUnsupportedError);
    expect(
      () => embeddings[0] = embedding.copyWith(vector: testVector384(seed: 7)),
      throwsUnsupportedError,
    );
  });
}
