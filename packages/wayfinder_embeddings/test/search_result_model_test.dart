import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('SearchResult', () {
    test('treats chunk, embedding, and similarity as part of equality', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );
      final embedding = Embedding(
        chunkId: chunk.id,
        source: 'test',
        modelName: 'fixture',
        vector: const [1.0, 0.0],
      );

      expect(
        SearchResult(chunk: chunk, embedding: embedding, similarity: 0.8),
        equals(
          SearchResult(chunk: chunk, embedding: embedding, similarity: 0.8),
        ),
      );
      expect(
        SearchResult(chunk: chunk, embedding: embedding, similarity: 0.8),
        isNot(equals(SearchResult(chunk: chunk, similarity: 0.8))),
      );
      expect(
        SearchResult(chunk: chunk, embedding: embedding, similarity: 0.8),
        isNot(
          equals(
            SearchResult(chunk: chunk, embedding: embedding, similarity: 0.7),
          ),
        ),
      );
    });

    test('round-trips through maps', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );
      final embedding = Embedding(
        chunkId: chunk.id,
        source: 'test',
        modelName: 'fixture',
        vector: const [1.0, 0.0],
      );
      final result = SearchResult(
        chunk: chunk,
        embedding: embedding,
        similarity: 0.8,
      );

      expect(SearchResult.fromMap(result.toMap()), result);
      expect(
        SearchResult.fromMap(
          SearchResult(chunk: chunk, similarity: 1.0).toMap(),
        ),
        SearchResult(chunk: chunk, similarity: 1.0),
      );
    });

    test('copyWith can clear optional embeddings', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );
      final embedding = Embedding(
        chunkId: chunk.id,
        source: 'test',
        modelName: 'fixture',
        vector: const [1.0, 0.0],
      );
      final result = SearchResult(
        chunk: chunk,
        embedding: embedding,
        similarity: 0.8,
      );

      expect(result.copyWith().embedding, embedding);
      expect(result.copyWith(embedding: null).embedding, isNull);
      expect(
        () => result.copyWith(embedding: 'not-an-embedding'),
        throwsArgumentError,
      );
    });

    test('accepts numeric similarity values from decoded JSON maps', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );

      final result = SearchResult.fromMap({
        'chunk': chunk.toMap(),
        'embedding': null,
        'similarity': 1,
      });

      expect(result.similarity, 1.0);
    });

    test('rejects non-finite similarity scores', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );

      expect(
        () => SearchResult(chunk: chunk, similarity: double.nan),
        throwsArgumentError,
      );
      expect(
        () => SearchResult.fromMap({
          'chunk': chunk.toMap(),
          'embedding': null,
          'similarity': double.infinity,
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed embedding payloads with a format error', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );

      expect(
        () => SearchResult.fromMap({
          'chunk': chunk.toMap(),
          'embedding': 'not-a-map',
          'similarity': 1.0,
        }),
        throwsFormatException,
      );
    });
  });
}
