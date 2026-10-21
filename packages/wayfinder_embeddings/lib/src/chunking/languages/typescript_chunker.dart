import '../../models/chunk.dart';
import '../../models/chunk_metadata.dart';
import '../../util/checks.dart';
import '../base_chunker.dart';
import '../chunk_budget.dart';

/// A pure-Dart structural chunker for TypeScript code.
///
/// Uses a brace-balanced, scope-aware state machine to accurately extract
/// classes, interfaces, methods, and functions without relying on external AST
/// parsers or fragile line-by-line regexes.
class TypeScriptChunker extends BaseChunker {
  TypeScriptChunker({int maxChunkLength = 1600})
    : maxChunkLength = checkPositive(maxChunkLength, 'maxChunkLength');

  static final _classPattern = RegExp(
    r'^\s*(?:export\s+)?(?:abstract\s+)?class\s+(\w+)',
    multiLine: true,
  );
  static final _interfacePattern = RegExp(
    r'^\s*(?:export\s+)?interface\s+(\w+)',
    multiLine: true,
  );
  static final _enumPattern = RegExp(
    r'^\s*(?:export\s+)?(?:const\s+)?enum\s+(\w+)',
    multiLine: true,
  );
  static final _namespacePattern = RegExp(
    r'^\s*(?:export\s+)?(?:declare\s+)?namespace\s+([\w.]+)',
    multiLine: true,
  );
  static final _typeAliasPattern = RegExp(
    r'^\s*(?:export\s+)?type\s+(\w+)',
    multiLine: true,
  );
  static final _functionPattern = RegExp(
    r'^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function(?:\s+(\w+))?',
    multiLine: true,
  );
  static final _methodPattern = RegExp(
    r'^\s*(?:public|private|protected)?\s*(?:static\s+)?(?:async\s+)?(\w+)\s*\(',
    multiLine: true,
  );
  static final _arrowMethodPattern = RegExp(
    r'^\s*(?:public|private|protected)?\s*(?:readonly\s+)?(?:static\s+)?(?:async\s+)?(\w+)\s*(?::\s*[^=]+)?\s*=\s*(?:async\s+)?(?:<[^>]+>\s*)?(?:\([^)]*\)|[\w$]+)\s*(?::\s*[^=]+)?\s*=>',
    multiLine: true,
  );
  static final _arrowFunctionPattern = RegExp(
    r'^\s*(?:export\s+)?(?:const|let|var)\s+(\w+)\s*(?::\s*[^=]+)?\s*=\s*(?:async\s+)?(?:<[^>]+>\s*)?(?:\([^)]*\)|[\w$]+)\s*(?::\s*[^=]+)?\s*=>',
    multiLine: true,
  );

  /// Upper bound for chunk text length, measured in non-whitespace characters.
  final int maxChunkLength;

  @override
  String get contentType => 'typescript';

  @override
  Set<String> get supportedExtensions => const {'typescript', '.ts', '.tsx'};

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) {
    if (content.trim().isEmpty) {
      return [];
    }

    final chunks = <Chunk>[];

    int braceLevel = 0;
    bool inSingleQuote = false;
    bool inDoubleQuote = false;
    bool inTemplate = false;
    bool inLineComment = false;
    bool inBlockComment = false;

    _ActiveBlock? currentTopLevel;
    _ActiveBlock? currentMemberFunction;

    int currentLine = 1;
    int statementStartPos = 0;

    final lines = content.split('\n');
    final lineStarts = _lineStarts(content);

    for (int i = 0; i < content.length; i++) {
      final char = content[i];
      final nextChar = (i + 1 < content.length) ? content[i + 1] : '';

      if (char == '\n') {
        inLineComment = false;
        currentLine++;
        continue;
      }

      if (inLineComment) continue;

      if (inBlockComment) {
        if (char == '*' && nextChar == '/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }

      if (inSingleQuote) {
        if (char == '\\') {
          i++;
          continue;
        }
        if (char == "'") inSingleQuote = false;
        continue;
      }

      if (inDoubleQuote) {
        if (char == '\\') {
          i++;
          continue;
        }
        if (char == '"') inDoubleQuote = false;
        continue;
      }

      if (inTemplate) {
        if (char == '\\') {
          i++;
          continue;
        }
        if (char == '`') inTemplate = false;
        continue;
      }

      if (char == '/' && nextChar == '/') {
        inLineComment = true;
        i++;
        continue;
      }
      if (char == '/' && nextChar == '*') {
        inBlockComment = true;
        i++;
        continue;
      }
      if (char == "'") {
        inSingleQuote = true;
        continue;
      }
      if (char == '"') {
        inDoubleQuote = true;
        continue;
      }
      if (char == '`') {
        inTemplate = true;
        continue;
      }

      if (braceLevel == 0 && char == ';') {
        final statement = content.substring(statementStartPos, i + 1).trim();
        final startLine = _signatureStartLine(
          content,
          statementStartPos,
          i + 1,
          lineStarts,
          fallback: currentLine,
        );
        final block =
            _typeAliasBlock(statement, startLine) ??
            _functionBlock(statement, startLine);
        if (block != null) {
          chunks.add(_buildChunk(block, currentLine, lines, metadata));
        }
        statementStartPos = i + 1;
      } else if (braceLevel == 1 && char == ';') {
        if (currentTopLevel?.type == 'class') {
          final statement = content.substring(statementStartPos, i + 1).trim();
          final arrowMethodMatch = _arrowMethodPattern.firstMatch(statement);
          if (arrowMethodMatch != null) {
            final startLine = _signatureStartLine(
              content,
              statementStartPos,
              i + 1,
              lineStarts,
              fallback: currentLine,
            );
            chunks.add(
              _buildChunk(
                _ActiveBlock(
                  'method',
                  arrowMethodMatch.group(1)!,
                  startLine,
                  parentKey: 'class',
                  parentName: currentTopLevel!.name,
                ),
                currentLine,
                lines,
                metadata,
              ),
            );
          }
        }
        statementStartPos = i + 1;
      }

      if (char == '{') {
        final signature = content.substring(statementStartPos, i).trim();
        final bodyStartLine = currentLine;
        final startLine = _signatureStartLine(
          content,
          statementStartPos,
          i,
          lineStarts,
          fallback: currentLine,
        );

        if (braceLevel == 0) {
          currentTopLevel = _topLevelBlock(signature, startLine, bodyStartLine);
        } else if (braceLevel == 1 && currentTopLevel?.type == 'class') {
          final match =
              _methodPattern.firstMatch(signature) ??
              _arrowMethodPattern.firstMatch(signature);
          if (match != null) {
            currentMemberFunction = _ActiveBlock(
              'method',
              match.group(1)!,
              startLine,
              bodyStartLine: bodyStartLine,
              parentKey: 'class',
              parentName: currentTopLevel!.name,
            );
          }
        } else if (braceLevel == 1 && currentTopLevel?.type == 'namespace') {
          currentMemberFunction = _namespaceFunctionBlock(
            signature,
            startLine,
            bodyStartLine,
            currentTopLevel!.name,
          );
        }

        braceLevel++;
        if (braceLevel == 1 || braceLevel == 2) {
          statementStartPos = i + 1;
        }
      } else if (char == '}') {
        braceLevel--;
        if (braceLevel < 0) braceLevel = 0;

        if (braceLevel == 0) {
          if (currentTopLevel != null) {
            chunks.add(
              _buildChunk(currentTopLevel, currentLine, lines, metadata),
            );
            currentTopLevel = null;
          }
        } else if (braceLevel == 1 &&
            currentMemberFunction != null &&
            (currentTopLevel?.type == 'class' ||
                currentTopLevel?.type == 'namespace')) {
          chunks.add(
            _buildChunk(currentMemberFunction, currentLine, lines, metadata),
          );
          currentMemberFunction = null;
        }

        if (braceLevel == 0 || braceLevel == 1) {
          statementStartPos = i + 1;
        }
      }
    }

    if (chunks.isEmpty) {
      chunks.add(
        Chunk(
          sourcePath: metadata.sourcePath,
          lineStart: 1,
          lineEnd: lines.length,
          content: content,
          type: 'file',
        ),
      );
    }

    // Filter out chunks that might have been wildly mismatched (safety bound)
    chunks.removeWhere((c) => c.lineStart > c.lineEnd);

    chunks.sort((a, b) => a.lineStart.compareTo(b.lineStart));
    return chunks;
  }

  Chunk _buildChunk(
    _ActiveBlock block,
    int endLine,
    List<String> lines,
    ChunkMetadata metadata,
  ) {
    int actualStart = block.startLine;
    while (actualStart > 1) {
      final prevLine = lines[actualStart - 2].trim();
      if (prevLine.startsWith('//') ||
          prevLine.startsWith('@') ||
          prevLine.startsWith('/*') ||
          prevLine.startsWith('*')) {
        actualStart--;
      } else {
        break;
      }
    }

    final safeStart = actualStart.clamp(1, lines.length);
    final safeEnd = endLine.clamp(1, lines.length);

    final fullContent = lines.sublist(safeStart - 1, safeEnd).join('\n');
    var chunkContent = fullContent;
    var chunkEnd = safeEnd;
    final metadataMap = <String, Object?>{
      if (block.type == 'class') 'class': block.name,
      if (block.type == 'enum') 'enum': block.name,
      if (block.type == 'interface') 'interface': block.name,
      if (block.type == 'namespace') 'namespace': block.name,
      if (block.type == 'type') 'typeAlias': block.name,
      if (block.type == 'method' || block.type == 'function')
        'function': block.name,
      if (block.parentKey != null && block.parentName != null)
        block.parentKey!: block.parentName,
    };

    if (block.bodyStartLine != null &&
        !fitsNonWhitespaceBudget(fullContent, maxChunkLength)) {
      final summaryEnd = block.bodyStartLine!.clamp(safeStart, safeEnd);
      final trimmed = lines
          .sublist(safeStart - 1, summaryEnd)
          .join('\n')
          .trimRight();
      final summary = trimmed.endsWith('{')
          ? trimmed.substring(0, trimmed.length - 1).trimRight()
          : trimmed;
      if (summary.isNotEmpty) {
        chunkContent = summary;
        chunkEnd = safeStart + summary.split('\n').length - 1;
        metadataMap['summary'] = true;
        metadataMap['truncated'] = true;
      }
    }

    return Chunk(
      sourcePath: metadata.sourcePath,
      lineStart: safeStart,
      lineEnd: chunkEnd,
      content: chunkContent,
      type: block.type,
      metadata: metadataMap,
    );
  }

  _ActiveBlock? _topLevelBlock(
    String signature,
    int startLine,
    int bodyStartLine,
  ) {
    final classMatch = _classPattern.firstMatch(signature);
    if (classMatch != null) {
      return _ActiveBlock(
        'class',
        classMatch.group(1)!,
        startLine,
        bodyStartLine: bodyStartLine,
      );
    }

    final enumMatch = _enumPattern.firstMatch(signature);
    if (enumMatch != null) {
      return _ActiveBlock(
        'enum',
        enumMatch.group(1)!,
        startLine,
        bodyStartLine: bodyStartLine,
      );
    }

    final interfaceMatch = _interfacePattern.firstMatch(signature);
    if (interfaceMatch != null) {
      return _ActiveBlock(
        'interface',
        interfaceMatch.group(1)!,
        startLine,
        bodyStartLine: bodyStartLine,
      );
    }

    final namespaceMatch = _namespacePattern.firstMatch(signature);
    if (namespaceMatch != null) {
      return _ActiveBlock(
        'namespace',
        namespaceMatch.group(1)!,
        startLine,
        bodyStartLine: bodyStartLine,
      );
    }

    final typeAlias = _typeAliasBlock(
      signature,
      startLine,
      bodyStartLine: bodyStartLine,
    );
    if (typeAlias != null) {
      return typeAlias;
    }

    return _functionBlock(signature, startLine, bodyStartLine);
  }

  _ActiveBlock? _namespaceFunctionBlock(
    String signature,
    int startLine,
    int bodyStartLine,
    String namespaceName,
  ) => switch (_functionBlock(signature, startLine, bodyStartLine)) {
    final block? => _ActiveBlock(
      block.type,
      block.name,
      block.startLine,
      bodyStartLine: block.bodyStartLine,
      parentKey: 'namespace',
      parentName: namespaceName,
    ),
    null => null,
  };

  _ActiveBlock? _functionBlock(
    String signature,
    int startLine, [
    int? bodyStartLine,
  ]) {
    final funcMatch = _functionPattern.firstMatch(signature);
    if (funcMatch != null) {
      return _ActiveBlock(
        'function',
        funcMatch.group(1) ?? 'default',
        startLine,
        bodyStartLine: bodyStartLine,
      );
    }

    final arrowMatch = _arrowFunctionPattern.firstMatch(signature);
    if (arrowMatch != null) {
      return _ActiveBlock(
        'function',
        arrowMatch.group(1)!,
        startLine,
        bodyStartLine: bodyStartLine,
      );
    }

    return null;
  }

  _ActiveBlock? _typeAliasBlock(
    String statement,
    int startLine, {
    int? bodyStartLine,
  }) => switch (_typeAliasPattern.firstMatch(statement)) {
    final match? => _ActiveBlock(
      'type',
      match.group(1)!,
      startLine,
      bodyStartLine: bodyStartLine,
    ),
    null => null,
  };

  List<int> _lineStarts(String content) {
    final starts = <int>[0];
    for (var i = 0; i < content.length; i++) {
      if (content[i] == '\n') {
        starts.add(i + 1);
      }
    }
    return starts;
  }

  int _signatureStartLine(
    String content,
    int start,
    int end,
    List<int> lineStarts, {
    required int fallback,
  }) {
    var offset = start;
    while (offset < end) {
      final char = content[offset];
      if (char != ' ' && char != '\t' && char != '\r' && char != '\n') {
        return _lineForOffset(lineStarts, offset);
      }
      offset++;
    }
    return fallback;
  }

  int _lineForOffset(List<int> lineStarts, int offset) {
    var low = 0;
    var high = lineStarts.length - 1;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final start = lineStarts[mid];
      if (start <= offset) {
        if (mid == lineStarts.length - 1 || lineStarts[mid + 1] > offset) {
          return mid + 1;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return 1;
  }
}

class _ActiveBlock {
  final String type;
  final String name;
  final int startLine;
  final int? bodyStartLine;
  final String? parentKey;
  final String? parentName;

  _ActiveBlock(
    this.type,
    this.name,
    this.startLine, {
    this.bodyStartLine,
    this.parentKey,
    this.parentName,
  });
}
