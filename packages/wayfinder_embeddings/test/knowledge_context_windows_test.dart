import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  const assembler = KnowledgeContextWindowAssembler();
  Future<int> characters(String text) async => text.runes.length;
  KnowledgeContextWindowInput input(
    String source,
    int start, {
    int? end,
    String sourceId = 'bundle-a',
    String path = 'discussion.md',
    String reason = 'match',
    double score = 0.9,
    List<String> requiredPaths = const [],
  }) => KnowledgeContextWindowInput(
    sourceId: sourceId,
    sourceText: source,
    requiredSourcePaths: requiredPaths,
    hit: KnowledgeContextHit(
      SearchResult(
        chunk: Chunk(
          sourcePath: path,
          lineStart: start,
          lineEnd: end ?? start,
          content: source
              .replaceAll('\r\n', '\n')
              .replaceAll('\r', '\n')
              .split('\n')
              .sublist(start - 1, end ?? start)
              .join('\n'),
          type: 'paragraph',
        ),
        embedding: null,
        similarity: score,
      ),
      reason,
    ),
  );

  test('adjacent correction is source context, not a changed match', () async {
    const source =
        '# Discussion\n\nSpeaker A: editors can delete.\n\nSpeaker B: correction, only owners can delete.\n\nEnd.';
    final selected = input(source, 3);
    final result = await assembler.assemble(
      [selected],
      options: KnowledgeContextWindowOptions(surroundingLines: 2),
      countTokens: characters,
    );
    final window = result.windows.single;
    expect(window.lineStart, 1);
    expect(window.lineEnd, 5);
    expect(window.content, source.split('\n').take(5).join('\n'));
    expect(window.inputs.single.hit, same(selected.hit));
    expect(selected.hit.result.chunk.content, 'Speaker A: editors can delete.');
    expect(selected.hit.result.similarity, 0.9);
    expect(result.diagnostics, isEmpty);
  });

  test(
    'overlapping and adjacent windows merge and retain every original provenance',
    () async {
      final source = List.generate(12, (i) => 'Line ${i + 1}').join('\n');
      final first = input(source, 3, score: 0.8);
      final second = input(source, 6, reason: 'relationship', score: 0.2);
      final result = await assembler.assemble(
        [first, second],
        options: KnowledgeContextWindowOptions(surroundingLines: 1),
        countTokens: characters,
      );
      final window = result.windows.single;
      expect((window.lineStart, window.lineEnd), (2, 7));
      expect(window.inputs.map((item) => item.hit), [first.hit, second.hit]);
      expect(
        (window.toJson()['passages'] as List).map((item) => item['chunkId']),
        [first.hit.result.chunk.id, second.hit.result.chunk.id],
      );
      expect(window.content.split('\n'), source.split('\n').sublist(1, 7));
    },
  );

  test(
    'equal relative paths in separate bundles never merge; budget is global',
    () async {
      final result = await assembler.assemble(
        [input('aaa', 1), input('bbb', 1, sourceId: 'bundle-b')],
        options: KnowledgeContextWindowOptions(
          surroundingLines: 0,
          maxTokens: 7,
        ),
        countTokens: characters,
      );
      // The joined source text costs eight, not six: separators are counted.
      expect(result.windows, hasLength(1));
      expect(result.windows.single.sourceId, 'bundle-a');
      expect(result.sourceTextTokens, 3);
      expect(result.diagnostics.single.code, 'context_window_omitted_budget');
      expect(result.diagnostics.single.details['sourceId'], 'bundle-b');
    },
  );

  test(
    'all selected core spans survive before optional surroundings',
    () async {
      const source = 'long surrounding context\nA\nmore surrounding context';
      final result = await assembler.assemble(
        [input(source, 2), input('B', 1, path: 'other.md')],
        options: KnowledgeContextWindowOptions(
          surroundingLines: 1,
          maxTokens: 4,
        ),
        countTokens: characters,
      );
      expect(result.windows.map((window) => window.content), ['A', 'B']);
      expect(result.appliedSurroundingLines, 0);
      expect(result.sourceTextTokens, 4);
      expect(result.diagnostics.map((item) => item.code), [
        'surrounding_context_reduced',
      ]);
    },
  );

  test(
    'oversized original source line is omitted whole, never truncated',
    () async {
      final selected = input('🦄${'x' * 100}', 1);
      final result = await assembler.assemble(
        [selected],
        options: KnowledgeContextWindowOptions(
          surroundingLines: 0,
          maxTokens: 10,
        ),
        countTokens: characters,
      );
      expect(result.windows, isEmpty);
      expect(result.sourceTextTokens, 0);
      expect(result.diagnostics.single.code, 'context_window_omitted_budget');
      expect(
        result.diagnostics.single.details['chunkId'],
        selected.hit.result.chunk.id,
      );
    },
  );

  test(
    'budget omission cannot retain subordinate without its governor',
    () async {
      final result = await assembler.assemble(
        [
          input('subordinate', 1, requiredPaths: ['governor.md']),
          input(
            'governing policy is long',
            1,
            path: 'governor.md',
            reason: 'governing',
          ),
        ],
        options: KnowledgeContextWindowOptions(
          surroundingLines: 0,
          maxTokens: 12,
        ),
        countTokens: characters,
      );
      expect(result.windows, isEmpty);
      expect(
        result.diagnostics.map((item) => item.code),
        containsAll([
          'context_window_omitted_budget',
          'governing_context_unavailable',
        ]),
      );
      expect(
        result.diagnostics.last.details['requiredSourcePath'],
        'governor.md',
      );
    },
  );

  test(
    'missing governor is explicit even when budget could fit subordinate',
    () async {
      final result = await assembler.assemble(
        [
          input('subordinate', 1, requiredPaths: ['missing.md']),
        ],
        options: KnowledgeContextWindowOptions(),
        countTokens: characters,
      );
      expect(result.windows, isEmpty);
      expect(result.diagnostics.single.code, 'governing_context_unavailable');
    },
  );

  test(
    'line boundaries clip at source limits and normalize newline forms',
    () async {
      const source = 'one\r\ntwo\rthree\n';
      final result = await assembler.assemble(
        [input(source, 2)],
        options: KnowledgeContextWindowOptions(surroundingLines: 20),
        countTokens: characters,
      );
      final window = result.windows.single;
      expect((window.lineStart, window.lineEnd), (1, 4));
      expect(window.content, 'one\ntwo\nthree\n');
    },
  );

  test(
    'indexed EOF code spans retain the chunker terminal-line convention',
    () async {
      const source = '```text\nunfinished code\n';
      final chunk = MarkdownChunker()
          .chunkContent(
            source,
            ChunkMetadata(sourcePath: 'unfinished.md', contentType: 'markdown'),
          )
          .single;
      expect(chunk.lineEnd, 3);
      final result = await assembler.assemble(
        [
          KnowledgeContextWindowInput(
            sourceId: 'bundle',
            sourceText: source,
            hit: KnowledgeContextHit(
              SearchResult(chunk: chunk, embedding: null, similarity: 0.9),
              'match',
            ),
          ),
        ],
        options: KnowledgeContextWindowOptions(surroundingLines: 20),
        countTokens: characters,
      );
      final window = result.windows.single;
      expect((window.lineStart, window.lineEnd), (1, 3));
      expect(window.content, source);
      expect(window.inputs.single.hit.result.chunk, same(chunk));
    },
  );

  test(
    'combined source text is measured once, not additive per-window estimates',
    () async {
      final counted = <String>[];
      final result = await assembler.assemble(
        [input('one', 1), input('two', 1, path: 'second.md')],
        options: KnowledgeContextWindowOptions(
          surroundingLines: 0,
          maxTokens: 10,
        ),
        countTokens: (text) async {
          counted.add(text);
          return 2 + text.length;
        },
      );
      expect(counted, ['one\n\ntwo']);
      expect(result.sourceTextTokens, 10);
      expect(
        result.toJson()['contextBudget'],
        containsPair('scope', 'window_source_text'),
      );
    },
  );

  test(
    'nonmonotonic token counts are checked at each candidate radius',
    () async {
      final result = await assembler.assemble(
        [input('one\ntwo\nthree\nfour\nfive', 3)],
        options: KnowledgeContextWindowOptions(
          surroundingLines: 2,
          maxTokens: 4,
        ),
        countTokens: (text) async => text.startsWith('two') ? 3 : 9,
      );
      expect(result.appliedSurroundingLines, 1);
      expect(result.sourceTextTokens, 3);
      expect(result.windows.single.content, 'two\nthree\nfour');
    },
  );

  test('duplicate input references terminate safely when omitted', () async {
    final selected = input('large line', 1);
    final result = await assembler.assemble(
      [selected, selected],
      options: KnowledgeContextWindowOptions(surroundingLines: 0, maxTokens: 1),
      countTokens: characters,
    );
    expect(result.windows, isEmpty);
    expect(result.diagnostics, hasLength(2));
  });

  test(
    'response adapter restores explicit governing context before selection',
    () async {
      final governor = input(
        'policy',
        1,
        path: 'governor.md',
        reason: 'governing',
      );
      final subordinate = input('detail', 1, path: 'detail.md');
      final response = KnowledgeSearchResponse(
        matches: [subordinate.hit.result],
        context: [governor.hit, subordinate.hit],
        notices: [],
        sourceTexts: {'governor.md': 'policy', 'detail.md': 'detail'},
        governingSources: {'detail.md': 'governor.md'},
      );
      final inputs = knowledgeContextWindowInputs(
        'bundle',
        response,
        selected: [subordinate.hit],
      );
      expect(inputs.map((input) => input.hit.reason), ['governing', 'match']);
      final result = await assembler.assemble(
        inputs,
        options: KnowledgeContextWindowOptions(
          surroundingLines: 0,
          maxTokens: 6,
        ),
        countTokens: characters,
      );
      expect(result.windows.map((window) => window.sourcePath), [
        'governor.md',
      ]);
      expect(result.diagnostics.single.code, 'context_window_omitted_budget');
      expect(response.matches.single, same(subordinate.hit.result));
    },
  );

  test(
    'invalid options, conflicting sources and out-of-range spans fail visibly',
    () async {
      expect(
        () => KnowledgeContextWindowOptions(surroundingLines: -1),
        throwsArgumentError,
      );
      expect(
        () => KnowledgeContextWindowOptions(surroundingLines: 101),
        throwsArgumentError,
      );
      expect(
        () => KnowledgeContextWindowOptions(maxTokens: 0),
        throwsArgumentError,
      );
      await expectLater(
        assembler.assemble(
          [input('one', 1), input('two', 1)],
          options: KnowledgeContextWindowOptions(),
          countTokens: characters,
        ),
        throwsArgumentError,
      );
      final invalid = KnowledgeContextWindowInput(
        sourceId: 'bundle',
        sourceText: 'one',
        hit: KnowledgeContextHit(
          SearchResult(
            chunk: Chunk(
              sourcePath: 'bad.md',
              lineStart: 2,
              lineEnd: 2,
              content: 'invalid',
              type: 'paragraph',
            ),
            embedding: null,
            similarity: 0,
          ),
          'match',
        ),
      );
      await expectLater(
        assembler.assemble(
          [invalid],
          options: KnowledgeContextWindowOptions(),
          countTokens: characters,
        ),
        throwsArgumentError,
      );
    },
  );
}
