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

  /// Groups prose within a section or explicitly labelled source block.
  ///
  /// This mode leaves size fitting to a tokenizer-aware consumer. The legacy
  /// character budget and paragraph boundaries remain unchanged by default.
  final bool groupSections;

  static final _headingPattern = RegExp(r'^(#{1,6})\s+(.+)$');
  static final _groupedHeadingPattern = RegExp(
    r'^ {0,3}(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$',
  );
  static final _fenceLinePrefixPattern = RegExp(r'^\s*(?:`{3,}|~{3,})');
  static final _listOrQuotePrefixPattern = RegExp(r'^\s*(?:[-+*>]|\d+[.)])\s');
  static final _setextUnderlinePattern = RegExp(r'^ {0,3}(=+|-+)\s*$');
  static final _fencePattern = RegExp(r'^(`{3,}|~{3,})(.*)$');
  static final _whitespacePattern = RegExp(r'\s+');
  static final _boldLabelPattern = RegExp(r'^\*\*[^*]+\*\*$');
  static final _transcriptTurnPattern = RegExp(
    r"^[\p{L}][\p{L}\p{M} .,'’\-]{1,80}\s{2,}\d{1,2}:\d{2}(?::\d{2})?",
    unicode: true,
  );
  static final _thematicBreakPattern = RegExp(
    r'^ {0,3}(?:-{3,}|\*{3,}|_{3,})\s*$',
  );
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
    this.groupSections = false,
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
    String? blockLabel;
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
        // Grouped prose can end in blank separator lines. Exclude those from
        // both its text and citation range, without trimming source content.
        if (groupSections) {
          while (currentBlock.endsWith('\n')) {
            currentBlock = currentBlock.substring(0, currentBlock.length - 1);
            lineEnd--;
          }
        }
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
            blockLabel: blockLabel,
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

      final headingMatch =
          (groupSections ? _groupedHeadingPattern : _headingPattern).firstMatch(
            rawLine,
          );
      final setext =
          groupSections &&
              !inCodeBlock &&
              trimmedLine.isNotEmpty &&
              !_fenceLinePrefixPattern.hasMatch(rawLine) &&
              !_listOrQuotePrefixPattern.hasMatch(rawLine) &&
              index + 1 < lines.length
          ? _setextUnderlinePattern.firstMatch(lines[index + 1])
          : null;
      if (!inCodeBlock && (headingMatch != null || setext != null)) {
        flushCurrentBlock(lineEnd: lineNumber - 1);
        blockLabel = null;

        final headingLevel =
            headingMatch?.group(1)?.length ??
            (setext!.group(1)!.startsWith('=') ? 1 : 2);
        final headingText = headingMatch?.group(2)?.trimRight() ?? trimmedLine;
        headings.removeWhere((h) => h.level >= headingLevel);
        headings.add((level: headingLevel, text: headingText));
        if (includeHeadings) {
          final headingChunk = _createChunk(
            sourcePath: metadata.sourcePath,
            lineStart: lineNumber,
            lineEnd: lineNumber + (setext == null ? 0 : 1),
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
        if (setext != null) index++;
        continue;
      }

      final fenceMatch = _fencePattern.firstMatch(trimmedLine);
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
          codeLanguage = fenceInfo.isEmpty
              ? null
              : fenceInfo.split(_whitespacePattern).first;
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
              blockLabel: blockLabel,
            ),
          );
        }
        index = end;
        continue;
      }

      if (trimmedLine.isEmpty) {
        if (groupSections &&
            currentBlock.isNotEmpty &&
            currentBlockType == 'paragraph') {
          currentBlock += '\n$rawLine';
        } else {
          flushCurrentBlock(lineEnd: lineNumber - 1);
        }
        continue;
      }

      if (groupSections) {
        // Explicit source formatting is a boundary, not a guess about a
        // person's identity or approval authority. Keep these labels with
        // the following prose; do not merge across two labelled messages.
        final label = _boldLabelPattern.hasMatch(trimmedLine);
        final turn = _transcriptTurnPattern.firstMatch(rawLine);
        final separator = _thematicBreakPattern.hasMatch(rawLine);
        if (label || turn != null || separator) {
          flushCurrentBlock(lineEnd: lineNumber - 1);
          blockLabel = turn?.group(0) ?? (label ? trimmedLine : null);
          if (separator) {
            currentBlock = rawLine;
            blockStartLine = lineNumber;
            flushCurrentBlock(lineEnd: lineNumber, type: 'separator');
            continue;
          }
        }
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

      if (!groupSections &&
          currentBlock.isNotEmpty &&
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

      if (!groupSections &&
          !fitsNonWhitespaceBudget(currentBlock, maxChunkLength) &&
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
    String? blockLabel,
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
        'blockLabel': ?blockLabel,
        if (headingLevel > 0) 'headingLevel': headingLevel,
        'parentHeadingId': ?parentHeadingId,
        'parentHeadingLevel': ?parentHeadingLevel,
      },
    );
  }
}
