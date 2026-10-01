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
  static final _footnoteDefinitionPattern = RegExp(r'^\[\^[^\]]+\]:');
  static final _indentedContinuationPattern = RegExp(r'^[ \t]');

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
    String? codeLanguage;
    String? codeFence;
    final headings = <({int level, String text})>[];

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
            headingPath: headings.map((h) => h.text).toList(),
            codeLanguage: codeLanguage,
          ),
        );
      }
      currentBlock = '';
      blockStartLine = null;
      codeLanguage = null;
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
        headings.removeWhere((h) => h.level >= headingLevel);
        headings.add((level: headingLevel, text: headingText));
        if (includeHeadings) {
          final headingChunk = _createChunk(
            sourcePath: metadata.sourcePath,
            lineStart: lineNumber,
            lineEnd: lineNumber,
            content: headingText,
            type: 'heading',
            headingLevel: headingLevel,
            headingPath: headings.map((h) => h.text).toList(),
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

      final fenceMatch = RegExp(r'^(`{3,}|~{3,})(.*)$').firstMatch(trimmedLine);
      final marker = fenceMatch?.group(1);
      final fenceInfo = fenceMatch?.group(2)?.trim() ?? '';
      final isFenceLine =
          marker != null &&
          (inCodeBlock
              ? marker[0] == codeFence![0] &&
                    marker.length >= codeFence.length &&
                    fenceInfo.isEmpty
              : marker[0] != '`' || !fenceInfo.contains('`'));
      if (isFenceLine) {
        if (inCodeBlock) {
          currentBlock += (currentBlock.isEmpty ? '' : '\n') + rawLine;
          flushCurrentBlock(
            lineEnd: lineNumber,
            type: 'code',
            emit: includeCodeBlocks,
          );
          inCodeBlock = false;
          codeFence = null;
        } else {
          flushCurrentBlock(lineEnd: lineNumber - 1);
          inCodeBlock = true;
          codeFence = marker;
          currentBlockType = 'code';
          blockStartLine = lineNumber;
          currentBlock = rawLine;
          final info = fenceInfo;
          codeLanguage = info.isEmpty ? null : info.split(RegExp(r'\s+')).first;
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
              headingPath: headings.map((h) => h.text).toList(),
              tableHeader: lines.sublist(index, index + 2).join('\n'),
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

      // A footnote definition and its indented continuation lines are
      // reference apparatus rather than prose. Keeping a run of definitions in
      // one `footnote` chunk stops a single short definition from competing
      // with body passages, and the type lets callers rank or exclude them.
      final definesFootnote = _footnoteDefinitionPattern.hasMatch(rawLine);
      final inFootnote =
          currentBlock.isNotEmpty && currentBlockType == 'footnote';
      if (definesFootnote
          ? !inFootnote
          : inFootnote && !_indentedContinuationPattern.hasMatch(rawLine)) {
        flushCurrentBlock(lineEnd: lineNumber - 1);
      }

      if (currentBlock.isNotEmpty &&
          currentBlockType != 'code' &&
          !appendFitsNonWhitespaceBudget(
            currentBlock,
            rawLine,
            maxChunkLength,
          )) {
        flushCurrentBlock(lineEnd: lineNumber - 1);
      }

      if (currentBlock.isEmpty) {
        blockStartLine = lineNumber;
        currentBlockType = definesFootnote ? 'footnote' : 'paragraph';
      }

      currentBlock += (currentBlock.isEmpty ? '' : '\n') + rawLine;

      if (!fitsNonWhitespaceBudget(currentBlock, maxChunkLength) &&
          currentBlockType != 'code') {
        flushCurrentBlock(lineEnd: lineNumber);
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
    List<String> headingPath = const [],
    String? codeLanguage,
    String? tableHeader,
  }) {
    return Chunk(
      sourcePath: sourcePath,
      lineStart: lineStart,
      lineEnd: lineEnd,
      content: content,
      type: type,
      metadata: {
        'headingPath': headingPath,
        'codeLanguage': ?codeLanguage,
        'tableHeader': ?tableHeader,
        if (headingLevel > 0) 'headingLevel': headingLevel,
        'parentHeadingId': ?parentHeadingId,
        'parentHeadingLevel': ?parentHeadingLevel,
      },
    );
  }
}
