import '../../models/chunk.dart';
import '../../models/chunk_metadata.dart';
import '../base_chunker.dart';
import '../chunk_budget.dart';

/// A chunker for plain text documents.
class TextChunker extends BaseChunker {
  /// The maximum non-whitespace character budget for a chunk.
  final int maxChunkLength;

  /// Whether to split on paragraphs.
  final bool splitOnParagraphs;

  /// Whether to split an over-budget paragraph on sentence boundaries.
  final bool splitOnSentences;

  @override
  String get contentType => 'text';

  @override
  Set<String> get supportedExtensions => const {'text', '.txt', '.text'};

  /// Creates a new text chunker.
  TextChunker({
    int maxChunkLength = 1000,
    this.splitOnParagraphs = true,
    this.splitOnSentences = false,
  }) : maxChunkLength = checkPositiveChunkConfig(
         maxChunkLength,
         'maxChunkLength',
       );

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) {
    final chunks = <Chunk>[];

    if (splitOnParagraphs) {
      final lineStarts = _lineStartOffsets(content);
      // Split on empty lines (paragraphs), tracking actual positions
      // in the original content to compute correct line numbers.
      final separatorPattern = RegExp(r'\n\s*\n');
      final paragraphs = content.split(separatorPattern);

      int searchFrom = 0;
      for (final paragraph in paragraphs) {
        if (paragraph.trim().isEmpty) continue;

        // Find the actual position of this paragraph in the original content
        final paragraphIndex = content.indexOf(paragraph, searchFrom);
        final lineStart = content
            .substring(0, paragraphIndex)
            .split('\n')
            .length;
        final paragraphLines = paragraph.split('\n');
        final lineEnd = lineStart + paragraphLines.length - 1;
        searchFrom = paragraphIndex + paragraph.length;

        if (splitOnSentences &&
            !fitsNonWhitespaceBudget(paragraph, maxChunkLength)) {
          // Split long paragraphs into sentences. Every line number comes from
          // the sentence offset inside the original content, so the ranges stay
          // exact for multi-line paragraphs.
          String currentChunk = '';
          int chunkStartOffset = paragraphIndex;
          int chunkEndOffset = paragraphIndex;

          void emitCurrentChunk() {
            chunks.add(
              Chunk(
                sourcePath: metadata.sourcePath,
                lineStart: _lineNumberAt(lineStarts, chunkStartOffset),
                lineEnd: _lineNumberAt(
                  lineStarts,
                  chunkEndOffset > chunkStartOffset
                      ? chunkEndOffset - 1
                      : chunkStartOffset,
                ),
                content: currentChunk,
                type: 'paragraph',
              ),
            );
          }

          for (final span in _sentenceSpans(paragraph)) {
            final sentence = paragraph.substring(span.start, span.end);
            final sentenceStart = paragraphIndex + span.start;
            final sentenceEnd = paragraphIndex + span.end;

            if (currentChunk.isEmpty ||
                appendFitsNonWhitespaceBudget(
                  currentChunk,
                  sentence,
                  maxChunkLength,
                )) {
              if (currentChunk.isEmpty) {
                chunkStartOffset = sentenceStart;
              } else {
                currentChunk += ' ';
              }
              currentChunk += sentence;
            } else {
              emitCurrentChunk();
              currentChunk = sentence;
              chunkStartOffset = sentenceStart;
            }
            chunkEndOffset = sentenceEnd;
          }

          // Add the final chunk
          if (currentChunk.isNotEmpty) {
            emitCurrentChunk();
          }
        } else {
          // Add the whole paragraph as a chunk
          chunks.add(
            Chunk(
              sourcePath: metadata.sourcePath,
              lineStart: lineStart,
              lineEnd: lineEnd,
              content: paragraph,
              type: 'paragraph',
            ),
          );
        }
      }
    } else {
      // Split by max length only
      if (fitsNonWhitespaceBudget(content, maxChunkLength)) {
        // Single chunk
        chunks.add(
          Chunk(
            sourcePath: metadata.sourcePath,
            lineStart: 1,
            lineEnd: content.split('\n').length,
            content: content,
            type: 'text',
          ),
        );
      } else {
        // Multiple chunks
        final lines = content.split('\n');

        String currentChunk = '';
        int chunkStartLine = 1;
        int currentLine = 1;

        for (final line in lines) {
          if (currentChunk.isEmpty ||
              appendFitsNonWhitespaceBudget(
                currentChunk,
                line,
                maxChunkLength,
              )) {
            currentChunk += (currentChunk.isEmpty ? '' : '\n') + line;
          } else {
            // Add the current chunk
            chunks.add(
              Chunk(
                sourcePath: metadata.sourcePath,
                lineStart: chunkStartLine,
                lineEnd: currentLine - 1,
                content: currentChunk,
                type: 'text',
              ),
            );

            // Start a new chunk
            currentChunk = line;
            chunkStartLine = currentLine;
          }

          currentLine++;
        }

        // Add the final chunk
        if (currentChunk.isNotEmpty) {
          chunks.add(
            Chunk(
              sourcePath: metadata.sourcePath,
              lineStart: chunkStartLine,
              lineEnd: currentLine - 1,
              content: currentChunk,
              type: 'text',
            ),
          );
        }
      }
    }

    return chunks;
  }
}

/// Splits [paragraph] on sentence boundaries and returns each span.
///
/// The spans are offsets inside [paragraph]. They match what
/// `paragraph.split(RegExp(r'(?<=[.!?])\s+'))` produces, but they also carry
/// the position each sentence starts at.
List<({int start, int end})> _sentenceSpans(String paragraph) {
  final spans = <({int start, int end})>[];
  var start = 0;
  for (final match in _sentenceSeparatorPattern.allMatches(paragraph)) {
    spans.add((start: start, end: match.start));
    start = match.end;
  }
  spans.add((start: start, end: paragraph.length));
  return spans;
}

final RegExp _sentenceSeparatorPattern = RegExp(r'(?<=[.!?])\s+');

/// Returns the offset at which each line of [content] starts.
List<int> _lineStartOffsets(String content) {
  final offsets = <int>[0];
  for (var index = 0; index < content.length; index++) {
    if (content.codeUnitAt(index) == 0x0A) {
      offsets.add(index + 1);
    }
  }
  return offsets;
}

/// Returns the 1-based line number that holds [offset].
int _lineNumberAt(List<int> lineStarts, int offset) {
  var low = 0;
  var high = lineStarts.length - 1;
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    if (lineStarts[middle] <= offset) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low + 1;
}
