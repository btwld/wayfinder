import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('ParentChildSearchResult', () {
    test('treats child result and parent chunk as part of equality', () {
      final parent = Chunk(
        id: 'parent',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 20,
        content: 'class AuthService {}',
        type: 'class',
      );
      final child = Chunk(
        id: 'child',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 5,
        lineEnd: 8,
        content: 'void refreshToken() {}',
        type: 'function',
      );
      final result = SearchResult(chunk: child, similarity: 0.8);

      expect(
        ParentChildSearchResult(child: result, parentChunk: parent),
        equals(ParentChildSearchResult(child: result, parentChunk: parent)),
      );
      expect(
        ParentChildSearchResult(child: result, parentChunk: parent),
        isNot(equals(ParentChildSearchResult(child: result))),
      );
    });

    test('round-trips through maps', () {
      final parent = Chunk(
        id: 'parent',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 20,
        content: 'class AuthService {}',
        type: 'class',
      );
      final child = Chunk(
        id: 'child',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 5,
        lineEnd: 8,
        content: 'void refreshToken() {}',
        type: 'function',
      );
      final result = ParentChildSearchResult(
        child: SearchResult(chunk: child, similarity: 0.8),
        parentChunk: parent,
      );

      expect(ParentChildSearchResult.fromMap(result.toMap()), result);
    });

    test('rejects malformed derived map fields when present', () {
      final parent = Chunk(
        id: 'parent',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 20,
        content: 'class AuthService {}',
        type: 'class',
      );
      final child = Chunk(
        id: 'child',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 5,
        lineEnd: 8,
        content: 'void refreshToken() {}',
        type: 'function',
      );
      final result = ParentChildSearchResult(
        child: SearchResult(chunk: child, similarity: 0.8),
        parentChunk: parent,
      );
      final map = result.toMap();

      expect(
        () => ParentChildSearchResult.fromMap({
          ...map,
          'contextChunk': 'not-a-map',
        }),
        throwsFormatException,
      );
      expect(
        () => ParentChildSearchResult.fromMap({...map, 'expanded': 'yes'}),
        throwsFormatException,
      );
      expect(
        () => ParentChildSearchResult.fromMap({
          ...map,
          'contextChunk': child.toMap(),
        }),
        throwsFormatException,
      );
      expect(
        () => ParentChildSearchResult.fromMap({...map, 'expanded': false}),
        throwsFormatException,
      );
    });
  });
}
