import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('HybridContentSearcher', () {
    test(
      'fuses lexical and semantic rankings with reciprocal rank fusion',
      () async {
        final lexicalOnly = Chunk(
          sourcePath: 'lib/session.dart',
          lineStart: 1,
          lineEnd: 5,
          content: 'refresh token session',
          type: 'function',
        );
        final shared = Chunk(
          sourcePath: 'lib/auth_controller.dart',
          lineStart: 1,
          lineEnd: 5,
          content: 'refresh refresh access token token controller',
          type: 'function',
        );
        final semanticOnly = Chunk(
          sourcePath: 'lib/use_auth.ts',
          lineStart: 1,
          lineEnd: 5,
          content: 'authentication hook',
          type: 'function',
        );

        final store = MemoryStore();
        for (final chunk in [lexicalOnly, shared, semanticOnly]) {
          await store.storeChunk(chunk);
        }
        await store.storeEmbedding(
          Embedding(
            chunkId: lexicalOnly.id,
            source: 'fake',
            modelName: 'dense',
            vector: const [0.0, 0.1],
          ),
        );
        await store.storeEmbedding(
          Embedding(
            chunkId: shared.id,
            source: 'fake',
            modelName: 'dense',
            vector: const [0.1, 0.9],
          ),
        );
        await store.storeEmbedding(
          Embedding(
            chunkId: semanticOnly.id,
            source: 'fake',
            modelName: 'dense',
            vector: const [1.0, 0.0],
          ),
        );

        final semanticSearcher = ContentSearcher(
          store: store,
          embedder: _FakeDenseEmbedder(
            queryVectors: {
              'refresh token': const [1.0, 0.0],
            },
          ),
        );
        final lexicalIndex = BM25LexicalIndex.fromChunks([
          lexicalOnly,
          shared,
          semanticOnly,
        ]);
        final hybridSearcher = HybridContentSearcher(
          lexicalIndex: lexicalIndex,
          semanticSearcher: semanticSearcher,
          candidateLimit: 3,
        );

        final results = await hybridSearcher.search('refresh token', limit: 3);

        expect(results, hasLength(3));
        expect(results.first.chunk.id, shared.id);
        expect(results.first.similarity, closeTo(1 / 61 + 1 / 62, 1e-12));
        expect(
          results.map((result) => result.chunk.id),
          containsAll([lexicalOnly.id, shared.id, semanticOnly.id]),
        );

        await store.close();
      },
    );
  });
}

class _FakeDenseEmbedder extends BaseEmbedder {
  _FakeDenseEmbedder({required Map<String, List<double>> queryVectors})
    : _queryVectors = queryVectors;

  final Map<String, List<double>> _queryVectors;

  @override
  String get sourceName => 'fake';

  @override
  String get modelName => 'dense';

  @override
  int get dimension => 2;

  @override
  Future<List<double>> generateEmbedding(String text) {
    throw UnimplementedError('Only query vectors are supported.');
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    final vector = _queryVectors[text];
    if (vector == null) {
      throw StateError('No query vector registered for "$text".');
    }
    return vector;
  }
}
