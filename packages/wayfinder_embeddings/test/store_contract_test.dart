import 'package:test/test.dart';
import 'package:wayfinder_embeddings/src/storage/embedding_key.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

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
            vector: testVector384(seed: index + 1),
          ),
        );
      }

      final match = await store.getEmbedding(
        chunk.id,
        source: 'dense',
        modelName: 'model-3',
      );

      expect(match?.modelName, 'model-3');
      expect(match?.vector, testVector384(seed: 4));
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

  group('embeddingIdentityKey', () {
    test('computes distinct keys when identity parts contain delimiters', () {
      final first = embeddingIdentityKey(
        chunkId: 'chunk::alpha',
        source: 'source',
        modelName: 'model',
      );
      final second = embeddingIdentityKey(
        chunkId: 'chunk',
        source: 'alpha::source',
        modelName: 'model',
      );

      expect(first, isNot(second));
    });
  });
}
