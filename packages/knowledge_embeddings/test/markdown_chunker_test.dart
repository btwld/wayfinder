import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownChunker', () {
    test(
      'preserves caller metadata on every block without changing identities',
      () {
        const content =
            '# Guide\n\nRead this.\n\n```dart\nmain() {}\n```\n\n'
            '| Key | Value |\n| --- | --- |\n| a | b |';
        final metadata = ChunkMetadata(
          sourcePath: 'guide.md',
          contentType: 'markdown',
        );
        final chunker = MarkdownChunker();
        final original = chunker.chunkContent(content, metadata);
        final updated = chunker.chunkContent(
          content,
          metadata.copyWith(
            additionalMetadata: {
              'status': 'deprecated',
              'verified': [
                {'by': 'human:reviewer', 'at': '2026-09-09T00:00:00Z'},
              ],
              'headingLevel': 99,
            },
          ),
        );
        expect(
          updated.map((chunk) => chunk.id),
          original.map((chunk) => chunk.id),
        );
        expect(updated.map((chunk) => chunk.type), [
          'heading',
          'paragraph',
          'code',
          'table',
        ]);
        for (final chunk in updated) {
          expect(chunk.metadata['status'], 'deprecated');
          expect(chunk.metadata['verified'], [
            {'by': 'human:reviewer', 'at': '2026-09-09T00:00:00Z'},
          ]);
        }
        expect(updated.first.metadata['headingLevel'], 1);
      },
    );
    test('keeps table examples inside code fences', () {
      const content =
          '```markdown\n| Key | Value |\n| --- | --- |\n| a | b |\n```';
      final metadata = ChunkMetadata(
        sourcePath: 'example.md',
        contentType: 'markdown',
      );
      final chunks = MarkdownChunker().chunkContent(content, metadata);
      expect(chunks, hasLength(1));
      expect(chunks.single.type, 'code');
      expect(chunks.single.content, content);
      expect(
        MarkdownChunker(
          includeCodeBlocks: false,
        ).chunkContent(content, metadata),
        isEmpty,
      );
    });

    test('excludes tables when requested and keeps their heading context', () {
      const content =
          '# Settings\n\n| Key | Value |\n| --- | --- |\n| a | b |\n\nAfter.';
      final metadata = ChunkMetadata(
        sourcePath: 'example.md',
        contentType: 'markdown',
      );
      final chunks = MarkdownChunker().chunkContent(content, metadata);
      final table = chunks.singleWhere((chunk) => chunk.type == 'table');
      expect(table.metadata['parentHeadingId'], chunks.first.id);
      expect(table.metadata['parentHeadingLevel'], 1);
      final withoutTables = MarkdownChunker(
        includeTables: false,
      ).chunkContent(content, metadata);
      expect(withoutTables.map((chunk) => chunk.content), [
        'Settings',
        'After.',
      ]);
    });

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

    test('groups footnote definitions into one apparatus chunk', () {
      const content =
          '# Findings\n'
          '\n'
          'The renderer places annotations.[^layout]\n'
          '\n'
          '[^layout]: Exported annotation layout sample\n'
          '    captured from the 31 July build\n'
          '[^budget]: Generation budget measurements\n'
          '\n'
          'Proceed with the export.\n';

      final chunks = MarkdownChunker().chunkContent(
        content,
        ChunkMetadata(sourcePath: 'feasibility.md', contentType: 'markdown'),
      );

      expect(chunks.map((chunk) => chunk.type), [
        'heading',
        'paragraph',
        'footnote',
        'paragraph',
      ]);
      final footnote = chunks[2];
      expect(
        footnote.content,
        '[^layout]: Exported annotation layout sample\n'
        '    captured from the 31 July build\n'
        '[^budget]: Generation budget measurements',
      );
      expect(footnote.lineStart, 5);
      expect(footnote.lineEnd, 7);
      expect(chunks.last.content, 'Proceed with the export.');
      expect(chunks.last.lineStart, 9);
    });

    test('keeps footnote runs within the configured budget', () {
      const content =
          '[^a]: alpha beta\n'
          '[^b]: gamma delta\n'
          '[^c]: epsilon zeta';

      final chunker = MarkdownChunker(maxChunkLength: 20);
      final chunks = chunker.chunkContent(
        content,
        ChunkMetadata(sourcePath: 'notes.md', contentType: 'markdown'),
      );

      expect(chunks.map((chunk) => chunk.type), everyElement('footnote'));
      expect(chunks, hasLength(3));
      for (final chunk in chunks) {
        expect(
          _nonWhitespaceLength(chunk.content),
          lessThanOrEqualTo(chunker.maxChunkLength),
        );
      }
    });

    test('treats a fenced footnote definition as code', () {
      const content = '```markdown\n[^label]: Cited source title\n```';

      final chunks = MarkdownChunker().chunkContent(
        content,
        ChunkMetadata(sourcePath: 'example.md', contentType: 'markdown'),
      );

      expect(chunks.single.type, 'code');
      expect(chunks.single.content, content);
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
