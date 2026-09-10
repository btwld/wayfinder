import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('ContentSearcher', () {
    late MemoryStore store;
    late FakeEmbedder embedder;
    late ContentSearcher searcher;

    setUp(() async {
      store = MemoryStore();

      final chunkA = Chunk(
        sourcePath: 'lib/services/auth_service.dart',
        lineStart: 1,
        lineEnd: 20,
        content: 'class AuthService {}',
        type: 'class',
        metadata: {'language': 'dart'},
      );
      final chunkB = Chunk(
        sourcePath: 'lib/controllers/auth_controller.dart',
        lineStart: 5,
        lineEnd: 30,
        content: 'login() {}',
        type: 'method',
        metadata: {'language': 'dart', 'feature': 'auth'},
      );
      final chunkC = Chunk(
        sourcePath: 'lib/frontend/useAuth.ts',
        lineStart: 1,
        lineEnd: 15,
        content: 'export const useAuth = () => {};',
        type: 'function',
        metadata: {'language': 'typescript'},
      );
      final chunkD = Chunk(
        sourcePath: 'lib/services/session_service.dart',
        lineStart: 1,
        lineEnd: 20,
        content: 'class SessionService {}',
        type: 'class',
        metadata: {'language': 'dart'},
      );
      final chunkE = Chunk(
        sourcePath: 'lib/services/token_service.dart',
        lineStart: 1,
        lineEnd: 18,
        content: 'class TokenService {}',
        type: 'class',
        metadata: {'language': 'dart'},
      );
      final chunkF = Chunk(
        sourcePath: 'lib/services/profile_service.dart',
        lineStart: 1,
        lineEnd: 18,
        content: 'class ProfileService {}',
        type: 'class',
        metadata: {'language': 'dart'},
      );

      await store.storeChunk(chunkA);
      await store.storeChunk(chunkB);
      await store.storeChunk(chunkC);
      await store.storeChunk(chunkD);
      await store.storeChunk(chunkE);
      await store.storeChunk(chunkF);

      await store.storeEmbedding(
        Embedding(
          chunkId: chunkA.id,
          source: 'fake',
          modelName: 'fake-model',
          vector: const [1.0, 0.0],
        ),
      );
      await store.storeEmbedding(
        Embedding(
          chunkId: chunkB.id,
          source: 'fake',
          modelName: 'fake-model',
          vector: const [0.7, 0.3],
        ),
      );
      await store.storeEmbedding(
        Embedding(
          chunkId: chunkC.id,
          source: 'fake',
          modelName: 'fake-model',
          vector: const [0.1, 0.9],
        ),
      );
      await store.storeEmbedding(
        Embedding(
          chunkId: chunkD.id,
          source: 'fake',
          modelName: 'fake-model',
          vector: const [0.95, 0.05],
        ),
      );
      await store.storeEmbedding(
        Embedding(
          chunkId: chunkE.id,
          source: 'fake',
          modelName: 'fake-model',
          vector: const [0.92, 0.08],
        ),
      );
      await store.storeEmbedding(
        Embedding(
          chunkId: chunkF.id,
          source: 'fake',
          modelName: 'fake-model',
          vector: const [0.91, 0.09],
        ),
      );

      embedder = FakeEmbedder(
        queryVectors: {
          'auth service': const [0.9, 0.1],
          'typescript hook': const [0.0, 1.0],
        },
      );

      searcher = ContentSearcher(store: store, embedder: embedder);
    });

    tearDown(() async {
      await store.close();
      await embedder.dispose();
    });

    test('applies file path filters', () async {
      final results = await searcher.search(
        'auth service',
        options: SearchOptions(filePaths: ['controllers/auth_controller.dart']),
      );

      expect(results, hasLength(1));
      expect(
        results.first.chunk.sourcePath,
        'lib/controllers/auth_controller.dart',
      );
    });

    test('applies glob filters', () async {
      final results = await searcher.search(
        'auth service',
        options: SearchOptions(filePatterns: ['lib/**/auth_*']),
      );

      expect(
        results.map((r) => r.chunk.sourcePath),
        containsAll([
          'lib/services/auth_service.dart',
          'lib/controllers/auth_controller.dart',
        ]),
      );
    });

    test('applies chunk type filters', () async {
      final results = await searcher.search(
        'auth service',
        options: SearchOptions(chunkTypes: ['method']),
      );

      expect(results, hasLength(1));
      expect(results.first.chunk.type, 'method');
    });

    test('applies metadata filters', () async {
      final results = await searcher.search(
        'auth service',
        options: SearchOptions(metadataFilters: {'feature': 'auth'}),
      );

      expect(results, hasLength(1));
      expect(results.first.chunk.metadata['feature'], 'auth');
    });

    test(
      'returns filtered subset when query targets alternate language',
      () async {
        final results = await searcher.search(
          'typescript hook',
          options: SearchOptions(metadataFilters: {'language': 'typescript'}),
        );

        expect(results, hasLength(1));
        expect(results.first.chunk.sourcePath, 'lib/frontend/useAuth.ts');
      },
    );

    test(
      'expands candidate window when top results are filtered out',
      () async {
        final results = await searcher.search(
          'auth service',
          limit: 2,
          options: SearchOptions(metadataFilters: {'language': 'typescript'}),
        );

        expect(results, hasLength(1));
        expect(results.first.chunk.sourcePath, 'lib/frontend/useAuth.ts');
      },
    );

    test('returns empty results when limit is not positive', () async {
      expect(await searcher.search('auth service', limit: 0), isEmpty);
      expect(await searcher.search('auth service', limit: -1), isEmpty);
    });

    test('normalizes query whitespace before embedding', () async {
      final results = await searcher.search('  auth service \n');

      expect(results, isNotEmpty);
      expect(embedder.generatedQueries, ['auth service']);
    });

    test('supports disabling query cache', () async {
      final uncached = ContentSearcher(
        store: store,
        embedder: embedder,
        maxCacheSize: 0,
      );

      final first = await uncached.search('auth service');
      final second = await uncached.search('auth service');

      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
    });

    test('rejects negative query cache sizes', () {
      expect(
        () =>
            ContentSearcher(store: store, embedder: embedder, maxCacheSize: -1),
        throwsArgumentError,
      );
    });
  });
}

class FakeEmbedder extends BaseEmbedder {
  FakeEmbedder({Map<String, List<double>>? queryVectors, int dimension = 2})
    : _queryVectors = Map.of(queryVectors ?? const {}),
      _dimension = dimension;

  final Map<String, List<double>> _queryVectors;
  final int _dimension;
  final List<String> generatedQueries = [];

  @override
  String get sourceName => 'fake';

  @override
  String get modelName => 'fake-model';

  @override
  int get dimension => _dimension;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    throw UnimplementedError('FakeEmbedder only supports query vectors.');
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    generatedQueries.add(text);
    final vector = _queryVectors[text];
    if (vector == null) {
      throw StateError('No query vector registered for "$text".');
    }
    return vector;
  }
}
