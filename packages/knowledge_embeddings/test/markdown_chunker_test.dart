import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownChunker', () {
    test('preserves code fences and correct line numbers', () {
      final content = [
        '# Heading',
        'Paragraph line 1.',
        'Paragraph line 2.',
        '',
        '```dart',
        'void main() {}',
        '```',
        '',
        '| Col | Value |',
        '| --- | ----- |',
        '| foo | bar |',
      ].join('\n');

      final chunker = MarkdownChunker(
        includeHeadings: true,
        includeCodeBlocks: true,
        includeTables: true,
      );

      final metadata = ChunkMetadata(
        sourcePath: 'test.md',
        contentType: 'markdown',
      );

      final chunks = chunker.chunkContent(content, metadata);

      final headingChunk = chunks.firstWhere(
        (chunk) => chunk.type == 'heading',
      );
      expect(headingChunk.content, 'Heading');
      expect(headingChunk.lineStart, 1);
      expect(headingChunk.lineEnd, 1);
      expect(headingChunk.metadata['headingLevel'], 1);

      final paragraphChunk = chunks.firstWhere(
        (chunk) => chunk.type == 'paragraph',
      );
      expect(paragraphChunk.lineStart, 2);
      expect(paragraphChunk.lineEnd, 3);

      final codeChunk = chunks.firstWhere((chunk) => chunk.type == 'code');
      expect(codeChunk.content.startsWith('```'), isTrue);
      expect(codeChunk.content.trim().endsWith('```'), isTrue);
      expect(codeChunk.lineStart, 5);
      expect(codeChunk.lineEnd, 7);

      final tableChunk = chunks.firstWhere((chunk) => chunk.type == 'table');
      expect(tableChunk.lineStart, 9);
      expect(tableChunk.lineEnd, 11);

      expect(chunks.every((c) => c.lineStart >= 1), isTrue);
    });

    test('budgets paragraphs by non-whitespace characters', () {
      const content =
          '# Notes\n'
          'alpha       beta\n'
          'gamma';

      final chunker = MarkdownChunker(maxChunkLength: 14);
      final metadata = ChunkMetadata(
        sourcePath: 'spaced.md',
        contentType: 'markdown',
      );

      final chunks = chunker.chunkContent(content, metadata);
      final paragraphs = chunks
          .where((chunk) => chunk.type == 'paragraph')
          .toList();

      expect(paragraphs, hasLength(1));
      expect(_nonWhitespaceLength(paragraphs.single.content), 14);
      expect(paragraphs.single.content.length, greaterThan(14));
    });

    test('splits paragraphs before exceeding the configured budget', () {
      const content =
          '# Notes\n'
          'alpha beta\n'
          'gamma delta\n'
          'epsilon zeta';

      final chunker = MarkdownChunker(maxChunkLength: 12);
      final metadata = ChunkMetadata(
        sourcePath: 'budget.md',
        contentType: 'markdown',
      );

      final paragraphs = chunker
          .chunkContent(content, metadata)
          .where((chunk) => chunk.type == 'paragraph')
          .toList();

      expect(paragraphs, hasLength(3));
      for (final paragraph in paragraphs) {
        expect(
          _nonWhitespaceLength(paragraph.content),
          lessThanOrEqualTo(chunker.maxChunkLength),
        );
      }
      expect(paragraphs.map((chunk) => chunk.lineStart), [2, 3, 4]);
      expect(paragraphs.map((chunk) => chunk.lineEnd), [2, 3, 4]);
    });

    test('rejects invalid chunk budgets', () {
      expect(
        () => MarkdownChunker(maxChunkLength: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
      expect(
        () => MarkdownChunker(maxChunkLength: -1),
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
