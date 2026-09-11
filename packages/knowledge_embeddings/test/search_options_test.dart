import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('SearchOptions', () {
    test('rejects blank filter values', () {
      expect(() => SearchOptions(filePaths: const ['']), throwsArgumentError);
      expect(
        () => SearchOptions(filePatterns: const [' ']),
        throwsArgumentError,
      );
      expect(() => SearchOptions(chunkTypes: const ['']), throwsArgumentError);
      expect(
        () => SearchOptions(metadataFilters: const {'': 'dart'}),
        throwsArgumentError,
      );
    });

    test('matches file path filters on path boundaries only', () {
      final options = SearchOptions(filePaths: const ['auth.dart']);
      final exactChunk = Chunk(
        sourcePath: '/repo/lib/auth.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'void auth() {}',
        type: 'function',
      );
      final substringChunk = Chunk(
        sourcePath: '/repo/lib/oauth.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'void oauth() {}',
        type: 'function',
      );

      expect(options.matchesFilters(exactChunk), isTrue);
      expect(options.matchesFilters(substringChunk), isFalse);
    });

    test('matches glob filters against normalized paths', () {
      final options = SearchOptions(filePatterns: const ['lib/**/auth_*']);
      final chunk = Chunk(
        sourcePath: r'C:\repo\lib\services\auth_service.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'class AuthService {}',
        type: 'class',
      );

      expect(options.matchesFilters(chunk), isTrue);
    });

    test('matches globstar patterns against root and nested paths', () {
      final options = SearchOptions(filePatterns: const ['**/*.dart']);
      final rootChunk = Chunk(
        sourcePath: 'main.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'void main() {}',
        type: 'function',
      );
      final nestedChunk = Chunk(
        sourcePath: 'lib/src/main.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'void main() {}',
        type: 'function',
      );
      final textChunk = Chunk(
        sourcePath: 'README.md',
        lineStart: 1,
        lineEnd: 1,
        content: '# Orbit',
        type: 'heading',
      );

      expect(options.matchesFilters(rootChunk), isTrue);
      expect(options.matchesFilters(nestedChunk), isTrue);
      expect(options.matchesFilters(textChunk), isFalse);
    });

    test('keeps metadata filter collection values immutable and detached', () {
      final allowedLanguages = ['dart'];
      final options = SearchOptions(
        metadataFilters: {'language': allowedLanguages},
      );
      final chunk = Chunk(
        sourcePath: '/tmp/source.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'void main() {}',
        type: 'function',
        metadata: const {'language': 'dart'},
      );

      allowedLanguages.clear();

      expect(options.matchesFilters(chunk), isTrue);
      expect(options.metadataFilters['language'], ['dart']);
      expect(
        () => (options.metadataFilters['language']! as List<Object?>).add('ts'),
        throwsUnsupportedError,
      );
    });
  });
}
