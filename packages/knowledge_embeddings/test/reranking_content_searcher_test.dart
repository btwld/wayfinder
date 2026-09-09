import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('RerankingContentSearcher', () {
    test('reranks a wider delegate candidate set before trimming', () async {
      final low = _searchResult('lib/low.dart', 'less relevant');
      final high = _searchResult('lib/high.dart', 'refresh token match');
      final options = SearchOptions(filePatterns: const ['lib/*.dart']);
      String? delegateQuery;
      int? delegateLimit;
      SearchOptions? delegateOptions;

      final reranker = _FakeReranker(
        scoresByPath: const {'lib/high.dart': 0.99, 'lib/low.dart': 0.1},
      );
      final searcher = RerankingContentSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          delegateQuery = query;
          delegateLimit = limit;
          delegateOptions = options;
          return [low, high];
        }),
        reranker: reranker,
        candidateLimit: 25,
      );

      final results = await searcher.search(
        '  refresh token ',
        limit: 1,
        options: options,
      );

      expect(delegateQuery, 'refresh token');
      expect(delegateLimit, 25);
      expect(identical(delegateOptions, options), isTrue);
      expect(reranker.queries, ['refresh token']);
      expect(reranker.limits, [1]);
      expect(reranker.candidateCounts, [2]);
      expect(results, hasLength(1));
      expect(results.single.chunk.sourcePath, 'lib/high.dart');
      expect(results.single.similarity, 0.99);
    });

    test('uses per-call candidate limit when provided', () async {
      final chunk = _searchResult('lib/auth.dart', 'auth');
      int? delegateLimit;

      final searcher = RerankingContentSearcher(
        searcher: _FakeSearcher((query, {limit = 5, options}) async {
          delegateLimit = limit;
          return [chunk];
        }),
        reranker: _FakeReranker(scoresByPath: const {'lib/auth.dart': 0.7}),
        candidateLimit: 50,
      );

      final results = await searcher.search(
        'auth',
        limit: 1,
        candidateLimit: 3,
      );

      expect(delegateLimit, 3);
      expect(results.single.similarity, 0.7);
    });

    test(
      'returns empty results without calling delegate for blank query',
      () async {
        var delegateCalled = false;
        final searcher = RerankingContentSearcher(
          searcher: _FakeSearcher((query, {limit = 5, options}) async {
            delegateCalled = true;
            return [_searchResult('lib/auth.dart', 'auth')];
          }),
          reranker: _FakeReranker(scoresByPath: const {}),
        );

        expect(await searcher.search('   '), isEmpty);
        expect(await searcher.search('auth', limit: 0), isEmpty);
        expect(delegateCalled, isFalse);
      },
    );

    test('rejects invalid candidate limits', () {
      expect(
        () => RerankingContentSearcher(
          searcher: _FakeSearcher(
            (query, {limit = 5, options}) async => const [],
          ),
          reranker: _FakeReranker(scoresByPath: const {}),
          candidateLimit: 0,
        ),
        throwsArgumentError,
      );

      final searcher = RerankingContentSearcher(
        searcher: _FakeSearcher(
          (query, {limit = 5, options}) async => const [],
        ),
        reranker: _FakeReranker(scoresByPath: const {}),
      );
      expect(
        () => searcher.search('auth', candidateLimit: 0),
        throwsArgumentError,
      );
    });
  });
}

SearchResult _searchResult(String sourcePath, String content) {
  return SearchResult(
    chunk: Chunk(
      sourcePath: sourcePath,
      lineStart: 1,
      lineEnd: 1,
      content: content,
      type: 'function',
    ),
    similarity: 0.1,
  );
}

class _FakeReranker extends SearchReranker {
  _FakeReranker({required this.scoresByPath});

  final Map<String, double> scoresByPath;
  final List<String> queries = [];
  final List<int?> limits = [];
  final List<int> candidateCounts = [];

  @override
  Future<List<SearchResult>> rerank({
    required String query,
    required List<SearchResult> candidates,
    int? limit,
  }) async {
    queries.add(query);
    limits.add(limit);
    candidateCounts.add(candidates.length);
    final sorted = candidates.map((candidate) {
      return candidate.copyWith(
        similarity: scoresByPath[candidate.chunk.sourcePath] ?? 0,
      );
    }).toList()..sort((a, b) => b.similarity.compareTo(a.similarity));
    return sorted.take(limit ?? sorted.length).toList(growable: false);
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
