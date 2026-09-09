import '../../models/chunk.dart';
import '../../models/chunk_metadata.dart';
import '../base_chunker.dart';
import '../chunk_budget.dart';

/// A chunker for Markdown documents.
class MarkdownChunker extends BaseChunker {
  /// The maximum non-whitespace character budget for a chunk.
  final int maxChunkLength;

  /// Whether to include headings in the chunks.
  final bool includeHeadings;

  /// Whether to include code blocks in the chunks.
  final bool includeCodeBlocks;

  /// Whether to include tables in the chunks.
  final bool includeTables;

  static final _headingPattern = RegExp(r'^(#{1,6})\s+(.+)$');
  static final _tableDelimiterPattern = RegExp(
    r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
  );

  @override
  String get contentType => 'markdown';

  @override
  Set<String> get supportedExtensions => const {'markdown', '.md', '.markdown'};

  /// Creates a new Markdown chunker.
  MarkdownChunker({
    int maxChunkLength = 1000,
    this.includeHeadings = true,
    this.includeCodeBlocks = true,
    this.includeTables = true,
  }) : maxChunkLength = checkPositiveChunkConfig(
         maxChunkLength,
         'maxChunkLength',
       );

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) {
    final lines = content.split('\n');
    final chunks = <Chunk>[];

    String? currentHeadingId;
    int? currentHeadingLevel;

    String currentBlock = '';
    String currentBlockType = 'paragraph';
    int? blockStartLine;
    bool inCodeBlock = false;

    void flushCurrentBlock({
      required int lineEnd,
      String? type,
      bool emit = true,
    }) {
      final lineStart = blockStartLine;
      if (currentBlock.isEmpty || lineStart == null) {
        return;
      }

      if (emit) {
        chunks.add(
          _createChunk(
            sourcePath: metadata.sourcePath,
            lineStart: lineStart,
            lineEnd: lineEnd,
            content: currentBlock,
            type: type ?? currentBlockType,
            parentHeadingId: currentHeadingId,
            parentHeadingLevel: currentHeadingLevel,
          ),
        );
      }
      currentBlock = '';
      blockStartLine = null;
    }

    for (var index = 0; index < lines.length; index++) {
      final lineNumber = index + 1;
      final rawLine = lines[index];
      final trimmedLine = rawLine.trim();

      final headingMatch = _headingPattern.firstMatch(rawLine);
      if (!inCodeBlock && headingMatch != null) {
        flushCurrentBlock(lineEnd: lineNumber - 1);

        final headingLevel = headingMatch.group(1)!.length;
        final headingText = headingMatch.group(2)!.trimRight();
        if (includeHeadings) {
          final headingChunk = _createChunk(
            sourcePath: metadata.sourcePath,
            lineStart: lineNumber,
            lineEnd: lineNumber,
            content: headingText,
            type: 'heading',
            headingLevel: headingLevel,
          );
          chunks.add(headingChunk);
          currentHeadingId = headingChunk.id;
          currentHeadingLevel = headingLevel;
        } else {
          currentHeadingId = null;
          currentHeadingLevel = null;
        }
        continue;
      }

      final isFenceLine = trimmedLine.startsWith('```');
      if (isFenceLine) {
        if (inCodeBlock) {
          currentBlock += (currentBlock.isEmpty ? '' : '\n') + rawLine;
          flushCurrentBlock(
            lineEnd: lineNumber,
            type: 'code',
            emit: includeCodeBlocks,
          );
          inCodeBlock = false;
        } else {
          flushCurrentBlock(lineEnd: lineNumber - 1);
          inCodeBlock = true;
          currentBlockType = 'code';
          blockStartLine = lineNumber;
          currentBlock = rawLine;
        }
        continue;
      }

      if (inCodeBlock) {
        currentBlock += '\n$rawLine';
        continue;
      }

      if (index + 1 < lines.length &&
          rawLine.contains('|') &&
          _tableDelimiterPattern.hasMatch(lines[index + 1])) {
        flushCurrentBlock(lineEnd: lineNumber - 1);
        var end = index + 1;
        while (end + 1 < lines.length && lines[end + 1].contains('|')) {
          end++;
        }
        if (includeTables) {
          chunks.add(
            _createChunk(
              sourcePath: metadata.sourcePath,
              lineStart: lineNumber,
              lineEnd: end + 1,
              content: lines.sublist(index, end + 1).join('\n'),
              type: 'table',
              parentHeadingId: currentHeadingId,
              parentHeadingLevel: currentHeadingLevel,
            ),
          );
        }
        index = end;
        continue;
      }

      if (trimmedLine.isEmpty) {
        flushCurrentBlock(lineEnd: lineNumber - 1);
        continue;
      }

      if (currentBlock.isNotEmpty &&
          currentBlockType == 'paragraph' &&
          !appendFitsNonWhitespaceBudget(
            currentBlock,
            rawLine,
            maxChunkLength,
          )) {
        flushCurrentBlock(lineEnd: lineNumber - 1, type: 'paragraph');
      }

      if (currentBlock.isEmpty) {
        blockStartLine = lineNumber;
        currentBlockType = 'paragraph';
      }

      currentBlock += (currentBlock.isEmpty ? '' : '\n') + rawLine;

      if (!fitsNonWhitespaceBudget(currentBlock, maxChunkLength) &&
          currentBlockType == 'paragraph') {
        flushCurrentBlock(lineEnd: lineNumber, type: 'paragraph');
      }
    }

    if (currentBlock.isNotEmpty && blockStartLine != null) {
      final blockType = inCodeBlock ? 'code' : currentBlockType;
      flushCurrentBlock(
        lineEnd: lines.length,
        type: blockType,
        emit: blockType != 'code' || includeCodeBlocks,
      );
    }

    return [
      for (final chunk in chunks)
        chunk.copyWith(
          metadata: {...metadata.additionalMetadata, ...chunk.metadata},
        ),
    ];
  }

  Chunk _createChunk({
    required String sourcePath,
    required int lineStart,
    required int lineEnd,
    required String content,
    required String type,
    String? parentHeadingId,
    int? parentHeadingLevel,
    int headingLevel = 0,
  }) {
    return Chunk(
      sourcePath: sourcePath,
      lineStart: lineStart,
      lineEnd: lineEnd,
      content: content,
      type: type,
      metadata: {
        if (headingLevel > 0) 'headingLevel': headingLevel,
        'parentHeadingId': ?parentHeadingId,
        'parentHeadingLevel': ?parentHeadingLevel,
      },
    );
  }
}
