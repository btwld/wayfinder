import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('ParentChildResolver', () {
    test(
      'uses symbol metadata when parent summaries do not enclose children',
      () {
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

        final resolver = ParentChildResolver(chunks: [parent, child]);
        final expanded = resolver.expand([
          SearchResult(chunk: child, similarity: 0.9),
        ]);

        expect(expanded, hasLength(1));
        expect(expanded.single.child.chunk.id, child.id);
        expect(expanded.single.contextChunk.id, parent.id);
        expect(expanded.single.parentChunk?.id, parent.id);
        expect(expanded.single.similarity, 0.9);
        expect(expanded.single.expanded, isTrue);
      },
    );

    test(
      'uses the smallest enclosing parent range when metadata is absent',
      () {
        final file = Chunk(
          sourcePath: 'lib/use_auth.ts',
          lineStart: 1,
          lineEnd: 120,
          content: 'whole file',
          type: 'file',
        );
        final parent = Chunk(
          sourcePath: 'lib/use_auth.ts',
          lineStart: 10,
          lineEnd: 60,
          content: 'export class UseAuth {}',
          type: 'class',
          metadata: const {'class': 'UseAuth'},
        );
        final child = Chunk(
          sourcePath: 'lib/use_auth.ts',
          lineStart: 25,
          lineEnd: 35,
          content: 'refreshSession() {}',
          type: 'method',
        );

        final resolver = ParentChildResolver(chunks: [file, parent, child]);
        final expanded = resolver.expand([
          SearchResult(chunk: child, similarity: 0.7),
        ]);

        expect(expanded.single.contextChunk.id, parent.id);
      },
    );

    test('uses namespace metadata for TypeScript namespace children', () {
      final parent = Chunk(
        sourcePath: 'lib/validation.ts',
        lineStart: 1,
        lineEnd: 5,
        content: 'export namespace Validation {}',
        type: 'namespace',
        metadata: const {'namespace': 'Validation'},
      );
      final child = Chunk(
        sourcePath: 'lib/validation.ts',
        lineStart: 2,
        lineEnd: 4,
        content: 'export function isEmail(value: string): boolean {}',
        type: 'function',
        metadata: const {'namespace': 'Validation', 'function': 'isEmail'},
      );

      final resolver = ParentChildResolver(chunks: [parent, child]);
      final expanded = resolver.expand([
        SearchResult(chunk: child, similarity: 0.8),
      ]);

      expect(expanded.single.contextChunk.id, parent.id);
      expect(expanded.single.expanded, isTrue);
    });

    test('deduplicates repeated parent contexts by default', () {
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

      final resolver = ParentChildResolver(
        chunks: [parent, firstChild, secondChild],
      );
      final expanded = resolver.expand([
        SearchResult(chunk: firstChild, similarity: 0.8),
        SearchResult(chunk: secondChild, similarity: 0.6),
      ]);

      expect(expanded, hasLength(1));
      expect(expanded.single.child.chunk.id, firstChild.id);
      expect(expanded.single.contextChunk.id, parent.id);
    });
  });
}
