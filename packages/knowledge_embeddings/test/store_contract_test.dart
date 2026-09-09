import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/src/storage/embedding_entities.dart';
import 'package:test/test.dart';

import 'support/store_contract.dart';

void main() {
  group('MemoryStore contract', () {
    runStoreContract(MemoryStore.new);
  });

  group('MemoryStore', () {
    test('resolves a full embedding identity without scanning', () async {
      final store = MemoryStore();
      final chunk = Chunk(
        sourcePath: 'lib/direct.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'direct',
        type: 'text',
      );
      await store.storeChunk(chunk);

      // Several models for the same chunk: only the identity key selects one.
      for (var index = 0; index < 5; index++) {
        await store.storeEmbedding(
          Embedding(
            chunkId: chunk.id,
            source: 'dense',
            modelName: 'model-$index',
            vector: testVector768(seed: index + 1),
          ),
        );
      }

      final match = await store.getEmbedding(
        chunk.id,
        source: 'dense',
        modelName: 'model-3',
      );

      expect(match?.modelName, 'model-3');
      expect(match?.vector, testVector768(seed: 4));
      expect(
        await store.getEmbedding(
          chunk.id,
          source: 'dense',
          modelName: 'model-missing',
        ),
        isNull,
      );
      await store.close();
    });
  });

  group('ObjectBoxStore scoring', () {
    test('converts cosine distance to cosine similarity', () {
      expect(objectBoxCosineDistanceToSimilarity(0.0), 1.0);
      expect(objectBoxCosineDistanceToSimilarity(0.25), 0.75);
      expect(objectBoxCosineDistanceToSimilarity(1.0), 0.0);
      expect(objectBoxCosineDistanceToSimilarity(2.0), -1.0);
      expect(objectBoxCosineDistanceToSimilarity(-0.25), 1.0);
      expect(objectBoxCosineDistanceToSimilarity(2.25), -1.0);
    });

    test('accepts only dimensions backed by the generated HNSW schema', () {
      expect(
        () => validateObjectBoxVectorDimension(kStandardEmbeddingDimension),
        returnsNormally,
      );

      expect(
        () => validateObjectBoxVectorDimension(
          1024,
          name: 'embedding.vector.length',
          context: 'for embedding chunk-1',
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'embedding.vector.length')
              .having(
                (error) => error.message,
                'message',
                allOf(contains('768-dimensional'), contains('chunk-1')),
              ),
        ),
      );
    });
  });

  group('EmbeddingEntity768', () {
    test('computes distinct keys when identity parts contain delimiters', () {
      final first = EmbeddingEntity768.computeKey(
        'chunk::alpha',
        'source',
        'model',
      );
      final second = EmbeddingEntity768.computeKey(
        'chunk',
        'alpha::source',
        'model',
      );

      expect(first, isNot(second));
    });
  });
}
