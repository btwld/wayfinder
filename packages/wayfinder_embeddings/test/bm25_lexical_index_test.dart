import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('BM25LexicalIndex', () {
    test('ranks chunks with exact BM25 scores without vector hashing', () {
      final authChunk = Chunk(
        sourcePath: 'lib/auth.dart',
        lineStart: 1,
        lineEnd: 8,
        content: 'refresh refresh access token session',
        type: 'function',
      );
      final paymentChunk = Chunk(
        sourcePath: 'lib/payment.dart',
        lineStart: 1,
        lineEnd: 8,
        content: 'capture payment invoice total',
        type: 'function',
      );

      final index = BM25LexicalIndex.fromChunks([paymentChunk, authChunk]);
      final results = index.search('refresh token', limit: 2);

      expect(results, hasLength(1));
      expect(results.single.chunk.id, authChunk.id);
      expect(results.single.embedding, isNull);
      expect(results.single.similarity, greaterThan(0));
    });

    test('applies search options before ranking', () {
      final dartChunk = Chunk(
        sourcePath: 'lib/auth.dart',
        lineStart: 1,
        lineEnd: 8,
        content: 'refresh token',
        type: 'function',
        metadata: {'language': 'dart'},
      );
      final tsChunk = Chunk(
        sourcePath: 'lib/auth.ts',
        lineStart: 1,
        lineEnd: 8,
        content: 'refresh token',
        type: 'function',
        metadata: {'language': 'typescript'},
      );

      final index = BM25LexicalIndex.fromChunks([dartChunk, tsChunk]);
      final results = index.search(
        'refresh token',
        options: SearchOptions(metadataFilters: {'language': 'typescript'}),
      );

      expect(results, hasLength(1));
      expect(results.single.chunk.id, tsChunk.id);
    });

    test('matches common code identifier word boundaries', () {
      final authChunk = Chunk(
        sourcePath: 'lib/auth.dart',
        lineStart: 1,
        lineEnd: 3,
        content: 'void refreshToken() {}',
        type: 'function',
      );
      final httpChunk = Chunk(
        sourcePath: 'lib/http_client.dart',
        lineStart: 1,
        lineEnd: 3,
        content: 'class HTTPClient {}',
        type: 'class',
      );
      final snakeCaseChunk = Chunk(
        sourcePath: 'lib/session.dart',
        lineStart: 1,
        lineEnd: 3,
        content: 'void revoke_session_token() {}',
        type: 'function',
      );

      final index = BM25LexicalIndex.fromChunks([
        authChunk,
        httpChunk,
        snakeCaseChunk,
      ]);

      expect(
        index.search('refresh token').map((result) => result.chunk.id),
        contains(authChunk.id),
      );
      expect(
        index.search('http client').map((result) => result.chunk.id),
        contains(httpChunk.id),
      );
      expect(
        index.search('session token').map((result) => result.chunk.id),
        contains(snakeCaseChunk.id),
      );
    });

    test('rejects invalid BM25 parameters', () {
      final chunk = Chunk(
        sourcePath: 'lib/auth.dart',
        lineStart: 1,
        lineEnd: 8,
        content: 'refresh token',
        type: 'function',
      );

      expect(
        () => BM25LexicalIndex.fromChunks([chunk], k1: 0),
        throwsArgumentError,
      );
      expect(
        () => BM25LexicalIndex.fromChunks([chunk], k1: double.nan),
        throwsArgumentError,
      );
      expect(
        () => BM25LexicalIndex.fromChunks([chunk], k1: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => BM25LexicalIndex.fromChunks([chunk], b: -0.1),
        throwsArgumentError,
      );
      expect(
        () => BM25LexicalIndex.fromChunks([chunk], b: 1.1),
        throwsArgumentError,
      );
      expect(
        () => BM25LexicalIndex.fromChunks([chunk], b: double.nan),
        throwsArgumentError,
      );
    });
  });
}
