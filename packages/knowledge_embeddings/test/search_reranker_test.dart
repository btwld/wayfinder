import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('TeiReranker', () {
    test(
      'posts query and candidate texts and returns reranked results',
      () async {
        late final Uri requestUri;
        late final String requestQuery;
        late final List<String> requestTexts;
        final reranker = TeiReranker(
          baseUrl: Uri.parse('http://127.0.0.1:8080'),
          transport:
              (
                uri, {
                required query,
                required texts,
                required requestTimeout,
              }) async {
                requestUri = uri;
                requestQuery = query;
                requestTexts = texts;
                return [
                  {'index': 1, 'score': 0.91},
                  {'index': 0, 'score': 0.12},
                ];
              },
        );
        try {
          final low = _searchResult('low.dart', 'less relevant implementation');
          final high = _searchResult(
            'high.dart',
            'refresh token implementation',
          );

          final results = await reranker.rerank(
            query: ' refresh token ',
            candidates: [low, high],
            limit: 1,
          );

          expect(requestUri.path, '/rerank');
          expect(requestQuery, 'refresh token');
          expect(requestTexts, [
            'less relevant implementation',
            'refresh token implementation',
          ]);
          expect(results, hasLength(1));
          expect(results.single.chunk.sourcePath, 'high.dart');
          expect(results.single.similarity, 0.91);
        } finally {
          await reranker.dispose();
        }
      },
    );

    test('accepts valid partial rerank responses', () async {
      final reranker = TeiReranker(
        baseUrl: Uri.parse('http://127.0.0.1:8080/rerank'),
        transport:
            (
              uri, {
              required query,
              required texts,
              required requestTimeout,
            }) async {
              return [
                {'index': 2, 'score': 0.91},
                {'index': 0, 'score': 0.42},
              ];
            },
      );
      try {
        final results = await reranker.rerank(
          query: 'refresh token',
          candidates: [
            _searchResult('low.dart', 'less relevant implementation'),
            _searchResult('ignored.dart', 'not returned by the reranker'),
            _searchResult('high.dart', 'refresh token implementation'),
          ],
          limit: 3,
        );

        expect(results.map((result) => result.chunk.sourcePath), [
          'high.dart',
          'low.dart',
        ]);
        expect(results.map((result) => result.similarity), [0.91, 0.42]);
      } finally {
        await reranker.dispose();
      }
    });

    test('normalizes rerank endpoints with a trailing slash', () async {
      late final Uri requestUri;
      final reranker = TeiReranker(
        baseUrl: Uri.parse('http://127.0.0.1:8080/rerank/'),
        transport:
            (
              uri, {
              required query,
              required texts,
              required requestTimeout,
            }) async {
              requestUri = uri;
              return [
                {'index': 0, 'score': 0.5},
              ];
            },
      );
      try {
        await reranker.rerank(
          query: 'refresh token',
          candidates: [_searchResult('auth.dart', 'refresh token')],
        );

        expect(requestUri.path, '/rerank');
      } finally {
        await reranker.dispose();
      }
    });

    test('rejects malformed rerank responses', () async {
      final reranker = TeiReranker(
        baseUrl: Uri.parse('http://127.0.0.1:8080/rerank'),
        transport:
            (
              uri, {
              required query,
              required texts,
              required requestTimeout,
            }) async {
              return [
                {'index': 3, 'score': 0.91},
              ];
            },
      );
      try {
        expect(
          () => reranker.rerank(
            query: 'refresh token',
            candidates: [_searchResult('low.dart', 'content')],
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('index 3 is outside candidate range'),
            ),
          ),
        );
      } finally {
        await reranker.dispose();
      }
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
