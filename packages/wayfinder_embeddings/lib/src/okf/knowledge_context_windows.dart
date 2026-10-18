import 'knowledge_index.dart';

/// Opt-in presentation policy. Retrieval, embeddings and indexed chunks do not
/// change. [maxTokens] bounds source text joined with two newline characters;
/// citations, JSON, original matches and diagnostic overhead are not included.
class KnowledgeContextWindowOptions {
  KnowledgeContextWindowOptions({
    this.surroundingLines = 12,
    this.maxTokens = 4096,
  }) {
    if (surroundingLines < 0 || surroundingLines > 100 || maxTokens < 1) {
      throw ArgumentError(
        'Use surroundingLines from 0 to 100 and positive maxTokens.',
      );
    }
  }

  /// At most 100 lines on either side bounds candidate-radius checks.
  final int surroundingLines;
  final int maxTokens;
}

/// One selected hit and its unchanged indexed source. [sourceId] distinguishes
/// bundles with equal relative paths. Dependencies are explicit consumer policy,
/// never inferred from source content or the retrieval score.
class KnowledgeContextWindowInput {
  KnowledgeContextWindowInput({
    required this.sourceId,
    required this.sourceText,
    required this.hit,
    Iterable<String> requiredSourcePaths = const [],
  }) : requiredSourcePaths = Set.unmodifiable(requiredSourcePaths);

  final String sourceId;
  final String sourceText;
  final KnowledgeContextHit hit;
  final Set<String> requiredSourcePaths;
}

/// An exact, normalized source-line range, separate from the original chunks.
/// [inputs] retain every contributing hit, score, range and relationship reason.
class KnowledgeContextWindow {
  KnowledgeContextWindow._({
    required this.sourceId,
    required this.sourcePath,
    required this.lineStart,
    required this.lineEnd,
    required this.content,
    required List<KnowledgeContextWindowInput> inputs,
    required List<int> indices,
    required this.rank,
  }) : inputs = List.unmodifiable(inputs),
       _indices = List.unmodifiable(indices);

  final String sourceId;
  final String sourcePath;
  final int lineStart;
  final int lineEnd;
  final String content;
  final List<KnowledgeContextWindowInput> inputs;
  final int rank;
  final List<int> _indices;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'sourcePath': sourcePath,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'content': content,
    'passages': [
      for (final input in inputs)
        {
          'chunkId': input.hit.result.chunk.id,
          'lineStart': input.hit.result.chunk.lineStart,
          'lineEnd': input.hit.result.chunk.lineEnd,
          'similarity': input.hit.result.similarity,
          'reason': input.hit.reason,
          'viaPath': ?input.hit.viaPath,
          'relationship': ?input.hit.fieldEdge?.name,
        },
    ],
  };
}

class KnowledgeContextWindowDiagnostic {
  KnowledgeContextWindowDiagnostic(this.code, Map<String, Object?> details)
    : details = Map.unmodifiable(details);

  final String code;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {'code': code, ...details};
}

class KnowledgeContextAssembly {
  KnowledgeContextAssembly._({
    required List<KnowledgeContextWindow> windows,
    required List<KnowledgeContextWindowDiagnostic> diagnostics,
    required this.sourceTextTokens,
    required this.options,
    required this.appliedSurroundingLines,
  }) : windows = List.unmodifiable(windows),
       diagnostics = List.unmodifiable(diagnostics);

  final List<KnowledgeContextWindow> windows;
  final List<KnowledgeContextWindowDiagnostic> diagnostics;
  final int sourceTextTokens;
  final KnowledgeContextWindowOptions options;
  final int appliedSurroundingLines;

  Map<String, Object?> toJson() => {
    'contextWindows': windows.map((window) => window.toJson()).toList(),
    'contextBudget': {
      'scope': 'window_source_text',
      'separator': '\n\n',
      'maxTokens': options.maxTokens,
      'usedTokens': sourceTextTokens,
      'requestedSurroundingLines': options.surroundingLines,
      'appliedSurroundingLines': appliedSurroundingLines,
      'excludes': [
        'citations',
        'metadata',
        'matches',
        'context',
        'diagnostics',
      ],
    },
    'contextDiagnostics': diagnostics.map((item) => item.toJson()).toList(),
  };
}

/// Assembles bounded surrounding context after ranking and global selection.
///
/// Overlapping or adjacent ranges merge only within one source identity/path.
/// Whole source lines are preserved (CRLF/CR normalize to LF). If necessary,
/// surrounding lines decrease uniformly to zero, then lowest-ranked complete
/// windows are omitted. Omission also removes any dependent subordinate hit.
/// Every reduction or omission is reported; text is never cut within a line.
/// The token counter must be deterministic; no monotonic tokenizer is assumed.
class KnowledgeContextWindowAssembler {
  const KnowledgeContextWindowAssembler();

  Future<KnowledgeContextAssembly> assemble(
    Iterable<KnowledgeContextWindowInput> inputs, {
    required KnowledgeContextWindowOptions options,
    required Future<int> Function(String) countTokens,
  }) async {
    final ordered = inputs.toList();
    final lines = <(String, String), List<String>>{};
    final texts = <(String, String), String>{};
    for (final input in ordered) {
      final chunk = input.hit.result.chunk;
      final key = (input.sourceId, chunk.sourcePath);
      final source = input.sourceText
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      if (texts[key] case final existing? when existing != source) {
        throw ArgumentError('Conflicting indexed sources: $key');
      }
      texts[key] = source;
      final sourceLines = lines.putIfAbsent(key, () => source.split('\n'));
      if (chunk.lineStart < 1 ||
          chunk.lineEnd < chunk.lineStart ||
          chunk.lineEnd > sourceLines.length) {
        throw ArgumentError('Hit outside indexed source lines: ${chunk.id}');
      }
    }
    final active = {for (var i = 0; i < ordered.length; i++) i};
    final diagnostics = <KnowledgeContextWindowDiagnostic>[];

    void omit(int index, String code, {Object? dependency}) {
      if (!active.remove(index)) return;
      final input = ordered[index];
      final chunk = input.hit.result.chunk;
      diagnostics.add(
        KnowledgeContextWindowDiagnostic(code, {
          'sourceId': input.sourceId,
          'sourcePath': chunk.sourcePath,
          'chunkId': chunk.id,
          'lineStart': chunk.lineStart,
          'lineEnd': chunk.lineEnd,
          'requiredSourcePath': ?dependency,
        }),
      );
    }

    void removeUngoverned() {
      var changed = true;
      while (changed) {
        changed = false;
        final retained = {
          for (final i in active)
            (ordered[i].sourceId, ordered[i].hit.result.chunk.sourcePath),
        };
        for (final i in active.toList()) {
          for (final required in ordered[i].requiredSourcePaths) {
            if (!retained.contains((ordered[i].sourceId, required))) {
              omit(i, 'governing_context_unavailable', dependency: required);
              changed = true;
              break;
            }
          }
        }
      }
    }

    List<KnowledgeContextWindow> build(int padding) {
      final grouped = <(String, String), List<int>>{};
      for (final index in active) {
        final input = ordered[index];
        grouped
            .putIfAbsent((
              input.sourceId,
              input.hit.result.chunk.sourcePath,
            ), () => [])
            .add(index);
      }
      final result = <KnowledgeContextWindow>[];
      for (final entry in grouped.entries) {
        final sourceLines = lines[entry.key]!;
        final spans = [
          for (final i in entry.value)
            (
              index: i,
              start: (ordered[i].hit.result.chunk.lineStart - padding).clamp(
                1,
                sourceLines.length,
              ),
              end: (ordered[i].hit.result.chunk.lineEnd + padding).clamp(
                1,
                sourceLines.length,
              ),
            ),
        ]..sort((a, b) => a.start.compareTo(b.start));
        var start = spans.first.start;
        var end = spans.first.end;
        var indices = <int>[spans.first.index];
        void emit() {
          indices.sort();
          result.add(
            KnowledgeContextWindow._(
              sourceId: entry.key.$1,
              sourcePath: entry.key.$2,
              lineStart: start,
              lineEnd: end,
              content: sourceLines.sublist(start - 1, end).join('\n'),
              inputs: indices.map((i) => ordered[i]).toList(),
              indices: indices,
              rank: indices.first,
            ),
          );
        }

        for (final span in spans.skip(1)) {
          if (span.start <= end + 1) {
            if (span.end > end) end = span.end;
            indices.add(span.index);
          } else {
            emit();
            start = span.start;
            end = span.end;
            indices = [span.index];
          }
        }
        emit();
      }
      return result..sort((a, b) => a.rank.compareTo(b.rank));
    }

    Future<int> measure(List<KnowledgeContextWindow> windows) async {
      if (windows.isEmpty) return 0;
      final tokens = await countTokens(
        windows.map((window) => window.content).join('\n\n'),
      );
      if (tokens < 0) throw StateError('Tokenizer returned a negative count.');
      return tokens;
    }

    removeUngoverned();
    var padding = options.surroundingLines;
    var windows = build(padding);
    var tokens = await measure(windows);
    while (tokens > options.maxTokens && padding > 0) {
      padding--;
      windows = build(padding);
      tokens = await measure(windows);
    }
    if (padding < options.surroundingLines) {
      diagnostics.add(
        KnowledgeContextWindowDiagnostic('surrounding_context_reduced', {
          'requestedLines': options.surroundingLines,
          'appliedLines': padding,
        }),
      );
    }
    while (tokens > options.maxTokens && windows.isNotEmpty) {
      final last = windows.last;
      for (final index in last._indices) {
        omit(index, 'context_window_omitted_budget');
      }
      removeUngoverned();
      windows = build(padding);
      tokens = await measure(windows);
    }
    return KnowledgeContextAssembly._(
      windows: windows,
      diagnostics: diagnostics,
      sourceTextTokens: tokens,
      options: options,
      appliedSurroundingLines: padding,
    );
  }
}

/// Builds inputs from selected hits, retaining explicit governing dependencies.
/// A governor selected by the engine is included even when a downstream global
/// passage limit omitted it. An unavailable governor remains a dependency so
/// the assembler reports and removes its subordinate rather than hiding it.
List<KnowledgeContextWindowInput> knowledgeContextWindowInputs(
  String sourceId,
  KnowledgeSearchResponse response, {
  Iterable<KnowledgeContextHit>? selected,
}) {
  final result = <KnowledgeContextWindowInput>[];
  final seen = <String>{};
  final visiting = <String>{};
  void add(KnowledgeContextHit hit) {
    final chunk = hit.result.chunk;
    if (seen.contains(chunk.id)) return;
    if (!visiting.add(chunk.sourcePath)) {
      throw ArgumentError('Cyclic governing context: ${chunk.sourcePath}');
    }
    final dependencies = <String>[];
    final governor = response.governingSources[chunk.sourcePath];
    if (governor != null) {
      dependencies.add(governor);
      if (response.context
              .where(
                (candidate) => candidate.result.chunk.sourcePath == governor,
              )
              .firstOrNull
          case final candidate?) {
        add(candidate);
      }
    }
    visiting.remove(chunk.sourcePath);
    final sourceText = response.sourceTexts[chunk.sourcePath];
    if (sourceText == null) {
      throw StateError(
        'Indexed source unavailable for context assembly: ${chunk.sourcePath}',
      );
    }
    seen.add(chunk.id);
    result.add(
      KnowledgeContextWindowInput(
        sourceId: sourceId,
        sourceText: sourceText,
        hit: hit,
        requiredSourcePaths: dependencies,
      ),
    );
  }

  for (final hit in selected ?? response.context) {
    add(hit);
  }
  return result;
}
