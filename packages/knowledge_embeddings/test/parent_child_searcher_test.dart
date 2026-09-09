import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('ParentChildSearcher', () {
    test('expands delegate search hits to parent context', () async {
      final parent = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'class AuthService',
        type: 'class',
        metadata: const {'name': 'AuthService'},
      );
      final child = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 12,
        lineEnd: 20,
        content: 'Future<Token> refreshToken() async => token;',
        type: 'method',
        metadata: const {'class': 'AuthService', 'name': 'refreshToken'},
      );

      final searcher = ParentChildSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          expect(query, 'refresh token');
          expect(limit, 10);
          expect(options, isNull);
          return [SearchResult(chunk: child, similarity: 0.92)];
        }),
        resolver: ParentChildResolver(chunks: [parent, child]),
      );

      final results = await searcher.search('refresh token', limit: 10);

      expect(results, hasLength(1));
      expect(results.single.child.chunk.id, child.id);
      expect(results.single.contextChunk.id, parent.id);
      expect(results.single.similarity, 0.92);
      expect(results.single.expanded, isTrue);
    });

    test('passes query options and limit to the delegate searcher', () async {
      final chunk = Chunk(
        sourcePath: 'lib/profile_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class ProfileService {}',
        type: 'class',
        metadata: const {'language': 'dart'},
      );
      final options = SearchOptions(
        metadataFilters: const {'language': 'dart'},
      );
      String? capturedQuery;
      int? capturedLimit;
      SearchOptions? capturedOptions;

      final searcher = ParentChildSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          capturedQuery = query;
          capturedLimit = limit;
          capturedOptions = options;
          return [SearchResult(chunk: chunk, similarity: 0.75)];
        }),
        resolver: ParentChildResolver(chunks: [chunk]),
      );

      final results = await searcher.search(
        'profile settings',
        limit: 7,
        options: options,
      );

      expect(results.single.contextChunk.id, chunk.id);
      expect(capturedQuery, 'profile settings');
      expect(capturedLimit, 7);
      expect(identical(capturedOptions, options), isTrue);
    });

    test('trims query text before delegating search', () async {
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );
      String? capturedQuery;

      final searcher = ParentChildSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          capturedQuery = query;
          return [SearchResult(chunk: chunk, similarity: 0.75)];
        }),
        resolver: ParentChildResolver(chunks: [chunk]),
      );

      final results = await searcher.search('  refresh token \n');

      expect(results.single.contextChunk.id, chunk.id);
      expect(capturedQuery, 'refresh token');
    });

    test('caps contextual results to the requested limit', () async {
      final first = Chunk(
        sourcePath: 'lib/accounts.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AccountService {}',
        type: 'class',
      );
      final second = Chunk(
        sourcePath: 'lib/billing.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class BillingService {}',
        type: 'class',
      );

      final searcher = ParentChildSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          return [
            SearchResult(chunk: first, similarity: 0.8),
            SearchResult(chunk: second, similarity: 0.7),
          ];
        }),
        resolver: ParentChildResolver(chunks: [first, second]),
      );

      final results = await searcher.search('service', limit: 1);

      expect(results, hasLength(1));
      expect(results.single.child.chunk.id, first.id);
    });

    test('can keep multiple child hits for the same parent context', () async {
      final parent = Chunk(
        sourcePath: 'lib/orders.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'class OrderService',
        type: 'class',
        metadata: const {'name': 'OrderService'},
      );
      final firstChild = Chunk(
        sourcePath: 'lib/orders.dart',
        lineStart: 10,
        lineEnd: 20,
        content: 'createOrder() {}',
        type: 'method',
        metadata: const {'class': 'OrderService', 'name': 'createOrder'},
      );
      final secondChild = Chunk(
        sourcePath: 'lib/orders.dart',
        lineStart: 30,
        lineEnd: 40,
        content: 'cancelOrder() {}',
        type: 'method',
        metadata: const {'class': 'OrderService', 'name': 'cancelOrder'},
      );

      final searcher = ParentChildSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          return [
            SearchResult(chunk: firstChild, similarity: 0.8),
            SearchResult(chunk: secondChild, similarity: 0.6),
          ];
        }),
        resolver: ParentChildResolver(
          chunks: [parent, firstChild, secondChild],
        ),
        deduplicateContexts: false,
      );

      final results = await searcher.search('orders');

      expect(results, hasLength(2));
      expect(results.map((result) => result.child.chunk.id), [
        firstChild.id,
        secondChild.id,
      ]);
      expect(results.map((result) => result.contextChunk.id), [
        parent.id,
        parent.id,
      ]);
    });

    test(
      'expands child candidate window to backfill deduplicated contexts',
      () async {
        final firstParent = Chunk(
          sourcePath: 'lib/orders.dart',
          lineStart: 1,
          lineEnd: 1,
          content: 'class OrderService',
          type: 'class',
          metadata: const {'name': 'OrderService'},
        );
        final firstChild = Chunk(
          sourcePath: 'lib/orders.dart',
          lineStart: 10,
          lineEnd: 20,
          content: 'createOrder() {}',
          type: 'method',
          metadata: const {'class': 'OrderService', 'name': 'createOrder'},
        );
        final secondChild = Chunk(
          sourcePath: 'lib/orders.dart',
          lineStart: 30,
          lineEnd: 40,
          content: 'cancelOrder() {}',
          type: 'method',
          metadata: const {'class': 'OrderService', 'name': 'cancelOrder'},
        );
        final secondParent = Chunk(
          sourcePath: 'lib/billing.dart',
          lineStart: 1,
          lineEnd: 1,
          content: 'class BillingService',
          type: 'class',
          metadata: const {'name': 'BillingService'},
        );
        final thirdChild = Chunk(
          sourcePath: 'lib/billing.dart',
          lineStart: 12,
          lineEnd: 18,
          content: 'refundOrder() {}',
          type: 'method',
          metadata: const {'class': 'BillingService', 'name': 'refundOrder'},
        );
        final allHits = [
          SearchResult(chunk: firstChild, similarity: 0.9),
          SearchResult(chunk: secondChild, similarity: 0.8),
          SearchResult(chunk: thirdChild, similarity: 0.7),
        ];
        final requestedLimits = <int>[];

        final searcher = ParentChildSearcher(
          searcher: _FakeSearcher((query, {limit = 5, options}) async {
            requestedLimits.add(limit);
            return allHits.take(limit).toList(growable: false);
          }),
          resolver: ParentChildResolver(
            chunks: [
              firstParent,
              firstChild,
              secondChild,
              secondParent,
              thirdChild,
            ],
          ),
        );

        final results = await searcher.search('order lifecycle', limit: 2);

        expect(requestedLimits, [2, 4]);
        expect(results, hasLength(2));
        expect(results.map((result) => result.contextChunk.id), [
          firstParent.id,
          secondParent.id,
        ]);
      },
    );

    test('can wrap a hybrid searcher directly', () async {
      final parent = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'class AuthService',
        type: 'class',
        metadata: const {'name': 'AuthService'},
      );
      final child = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 12,
        lineEnd: 20,
        content: 'Future<Token> refreshToken() async => token;',
        type: 'method',
        metadata: const {'class': 'AuthService', 'name': 'refreshToken'},
      );
      final store = MemoryStore();
      addTearDown(store.close);
      await store.storeChunk(parent);
      await store.storeChunk(child);
      await store.storeEmbedding(
        Embedding(
          chunkId: child.id,
          source: 'fake',
          modelName: 'dense',
          vector: const [1.0, 0.0],
        ),
      );

      final hybridSearcher = HybridContentSearcher(
        lexicalIndex: BM25LexicalIndex.fromChunks([parent, child]),
        semanticSearcher: ContentSearcher(
          store: store,
          embedder: _FakeDenseEmbedder(
            queryVectors: {
              'refresh token': const [1.0, 0.0],
            },
          ),
        ),
        candidateLimit: 2,
      );
      final searcher = ParentChildSearcher(
        searcher: hybridSearcher,
        resolver: ParentChildResolver(chunks: [parent, child]),
      );

      final results = await searcher.search('refresh token', limit: 1);

      expect(results, hasLength(1));
      expect(results.single.child.chunk.id, child.id);
      expect(results.single.contextChunk.id, parent.id);
    });
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

/// A [Searcher] backed by one closure.
class _FakeSearcher implements Searcher {
  _FakeSearcher(this._onSearch);

  final Future<List<SearchResult>> Function(
    String query, {
    int limit,
    SearchOptions? options,
  })
  _onSearch;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    SearchOptions? options,
  }) => _onSearch(query, limit: limit, options: options);
}
