import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('TextChunker', () {
    test('splits paragraphs and preserves estimated line ranges', () {
      final chunker = TextChunker();
      final metadata = ChunkMetadata(
        sourcePath: 'docs/note.txt',
        contentType: 'text',
      );

      const content =
          'First paragraph line one.\n'
          'Continues on line two.\n'
          '\n'
          'Second paragraph alone.';

      final chunks = chunker.chunkContent(content, metadata);

      expect(chunks, hasLength(2));
      expect(chunks.first.lineStart, 1);
      expect(chunks.first.lineEnd, greaterThanOrEqualTo(2));
      expect(chunks.last.lineStart, greaterThan(chunks.first.lineStart));
      expect(chunks.last.type, 'paragraph');
    });

    test(
      'splits long paragraphs into sentence-based chunks when configured',
      () {
        final chunker = TextChunker(
          maxChunkLength: 50,
          splitOnParagraphs: true,
          splitOnSentences: true,
        );
        final metadata = ChunkMetadata(
          sourcePath: 'docs/long.txt',
          contentType: 'text',
        );

        const content =
            'Sentence one is brief. Sentence two stays short. '
            'Sentence three remains concise. Sentence four ends here.';

        final chunks = chunker.chunkContent(content, metadata);

        expect(chunks.length, greaterThan(1));
        for (final chunk in chunks) {
          expect(
            _nonWhitespaceLength(chunk.content),
            lessThanOrEqualTo(chunker.maxChunkLength),
          );
          expect(chunk.lineStart, 1);
          expect(chunk.lineEnd, 1);
          expect(chunk.type, 'paragraph');
        }
      },
    );

    test('chunks plain text when paragraph splitting disabled', () {
      final chunker = TextChunker(maxChunkLength: 20, splitOnParagraphs: false);
      final metadata = ChunkMetadata(
        sourcePath: 'docs/plain.txt',
        contentType: 'text',
      );

      const content =
          'alpha beta gamma\n'
          'delta epsilon zeta\n'
          'eta theta iota';

      final chunks = chunker.chunkContent(content, metadata);

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.type == 'text'), isTrue);
    });

    test('budgets plain text chunks by non-whitespace characters', () {
      final chunker = TextChunker(maxChunkLength: 14, splitOnParagraphs: false);
      final metadata = ChunkMetadata(
        sourcePath: 'docs/spaced.txt',
        contentType: 'text',
      );

      const content =
          'alpha     beta\n'
          '\n'
          'gamma';

      final chunks = chunker.chunkContent(content, metadata);

      expect(chunks, hasLength(1));
      expect(_nonWhitespaceLength(chunks.single.content), 14);
      expect(chunks.single.content.length, greaterThan(chunker.maxChunkLength));
    });

    test('reports the real line range of each sentence chunk', () {
      final chunker = TextChunker(
        maxChunkLength: 30,
        splitOnParagraphs: true,
        splitOnSentences: true,
      );
      final metadata = ChunkMetadata(
        sourcePath: 'docs/lines.txt',
        contentType: 'text',
      );

      const content =
          'Intro line.\n'
          '\n'
          'Sentence one is here.\n'
          'Sentence two is here.\n'
          'Sentence three is here.';

      final chunks = chunker.chunkContent(content, metadata);

      expect(chunks.first.lineStart, 1);
      expect(chunks.first.lineEnd, 1);

      final sentenceChunks = chunks.skip(1).toList();
      expect(sentenceChunks, hasLength(3));
      expect(sentenceChunks[0].lineStart, 3);
      expect(sentenceChunks[0].lineEnd, 3);
      expect(sentenceChunks[1].lineStart, 4);
      expect(sentenceChunks[1].lineEnd, 4);
      expect(sentenceChunks[2].lineStart, 5);
      expect(sentenceChunks[2].lineEnd, 5);
    });

    test('rejects invalid numeric configuration', () {
      expect(
        () => TextChunker(maxChunkLength: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
      expect(
        () => TextChunker(maxChunkLength: -1),
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
