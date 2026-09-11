import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('DartChunker', () {
    test('captures classes, members, and top-level declarations', () {
      final content = [
        'class Greeter {',
        '  Greeter();',
        '',
        "  String get message => 'hi';",
        '',
        '  void greet() {',
        '    print(message);',
        '  }',
        '',
        '  static void helper() {}',
        '}',
        '',
        'extension GreeterX on Greeter {',
        '  void wave() {}',
        '}',
        '',
        'mixin Logger {',
        '  void log(String value) {}',
        '}',
        '',
        'void topLevel() {}',
      ].join('\n');

      final chunker = DartChunker();
      final metadata = ChunkMetadata(
        sourcePath: 'greeter.dart',
        contentType: 'dart',
      );

      final chunks = chunker.chunkContent(content, metadata);

      final classChunk = chunks.firstWhere((chunk) => chunk.type == 'class');
      expect(classChunk.metadata['name'], 'Greeter');

      final methodChunk = chunks.firstWhere(
        (chunk) => chunk.metadata['name'] == 'greet',
      );
      expect(methodChunk.type, 'method');
      expect(methodChunk.metadata['class'], 'Greeter');

      final getterChunk = chunks.firstWhere(
        (chunk) => chunk.metadata['name'] == 'message',
      );
      expect(getterChunk.type, 'getter');

      final extensionMethod = chunks.firstWhere(
        (chunk) => chunk.metadata['name'] == 'wave',
      );
      expect(extensionMethod.metadata['extension'], 'GreeterX');

      final mixinMethod = chunks.firstWhere(
        (chunk) => chunk.metadata['name'] == 'log',
      );
      expect(mixinMethod.metadata['mixin'], 'Logger');

      final topLevel = chunks.firstWhere((chunk) => chunk.type == 'function');
      expect(topLevel.metadata['name'], 'topLevel');

      expect(classChunk.lineStart, equals(1));
      expect(classChunk.lineEnd, greaterThanOrEqualTo(classChunk.lineStart));
    });

    test('budgets function summaries by non-whitespace characters', () {
      final content = [
        'void padded() {',
        '        final value = 1;',
        '}',
      ].join('\n');

      final chunker = DartChunker(maxChunkLength: 27);
      final metadata = ChunkMetadata(
        sourcePath: 'padded.dart',
        contentType: 'dart',
      );

      final chunks = chunker.chunkContent(content, metadata);
      final functionChunk = chunks.singleWhere(
        (chunk) => chunk.type == 'function',
      );

      expect(functionChunk.content, contains('final value = 1'));
      expect(functionChunk.metadata['summary'], isNull);
      expect(_nonWhitespaceLength(functionChunk.content), 27);
      expect(functionChunk.content.length, greaterThan(chunker.maxChunkLength));
    });

    test('rejects invalid chunk budgets', () {
      expect(
        () => DartChunker(maxChunkLength: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
      expect(
        () => DartChunker(maxChunkLength: -1),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
    });
  });
}

int _nonWhitespaceLength(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').length;
}
