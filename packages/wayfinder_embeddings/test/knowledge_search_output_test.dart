import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

/// The search Markdown hosts render as tool text, and the JSON beside it.
void main() {
  test('project Markdown has ## Matches and ## Related Context with resolved '
      'sources, while the JSON keeps them raw', () async {
    final temp = await Directory.systemTemp.createTemp(
      'wayfinder-markdown-sources-',
    );
    addTearDown(() => temp.delete(recursive: true));
    await Directory(
      p.join(temp.path, 'billing', 'raw exports'),
    ).create(recursive: true);
    await File(p.join(temp.path, 'billing', 'Makefile')).writeAsString('');
    final matchA = SearchResult(
      chunk: Chunk(
        id: 'c1',
        sourcePath: 'billing/invoicing.md',
        lineStart: 10,
        lineEnd: 20,
        content: 'Direct match A body.',
        type: 'paragraph',
        metadata: {
          'okf': {
            'frontmatter': {
              'type': 'Specification',
              'title': 'Invoicing',
              'status': 'stable',
              'sources': [
                {
                  'id': 'S1',
                  'resource': '../../captures/pkg/analysis.md#finding-2',
                },
                {'id': 'S2', 'resource': '/references/revenue.v2.md#table-1'},
                {'id': 'S3', 'resource': 'references/source notes.md'},
                {'id': 'S4', 'resource': './references/other notes.md'},
                {'id': 'S5', 'resource': 'references/evidence.parquet'},
                {'id': 'S6', 'resource': 'Makefile'},
                {'id': 'S7', 'resource': 'raw exports'},
                {'id': 'S8', 'resource': 'données/rapport_été.md'},
                {'id': 'S9', 'resource': 'acme.sales'},
                {'id': 'S10', 'resource': 'all queries in acme.sales'},
                {'id': 'S11', 'resource': 'extracted PDF/OOXML text'},
                {'id': 'S12', 'resource': '//docs.example.test/spec'},
                {
                  'id': 'S13',
                  'resource': 'references/evidence.parquet?download=1#row-4',
                },
                {'id': 'S14', 'resource': 'FY2026/Q1'},
                {'id': 'S15', 'resource': 'archive/%FF.md'},
                {'id': 'S16', 'resource': '/../outside.txt'},
                {'resource': 'https://example.test/spec#s1'},
              ],
            },
            'headingPath': ['Rules', 'Timing'],
          },
        },
      ),
      embedding: null,
      similarity: 0.91,
    );
    final matchB = SearchResult(
      chunk: Chunk(
        id: 'c2',
        sourcePath: 'billing/terms.md',
        lineStart: 1,
        lineEnd: 5,
        content: 'Direct match B body.',
        type: 'paragraph',
      ),
      embedding: null,
      similarity: 0.82,
    );
    final relatedHit = KnowledgeContextHit(
      SearchResult(
        chunk: Chunk(
          id: 'c3',
          sourcePath: 'billing/oq-12.md',
          lineStart: 4,
          lineEnd: 9,
          content: 'Related question body.',
          type: 'paragraph',
        ),
        embedding: null,
        similarity: 0.65,
      ),
      'relationship',
      viaPath: 'billing/invoicing.md',
    );
    final matchBRelationHit = KnowledgeContextHit(
      matchB,
      'relationship',
      viaPath: 'billing/invoicing.md',
    );
    final response = KnowledgeSearchResponse(
      matches: [matchA, matchB],
      // Even if context only had room for matchA + relatedHit, matchB stays in ## Matches.
      context: [
        KnowledgeContextHit(matchA, 'match'),
        matchBRelationHit,
        relatedHit,
      ],
      notices: const [],
      sourcePaths: const {
        'billing/invoicing.md': {
          '../../captures/pkg/analysis.md#finding-2':
              '../captures/pkg/analysis.md',
          '/references/revenue.v2.md#table-1': 'references/revenue.v2.md',
          'references/source notes.md': 'billing/references/source notes.md',
          './references/other notes.md': 'billing/references/other notes.md',
          'references/evidence.parquet': 'billing/references/evidence.parquet',
          'Makefile': 'billing/Makefile',
          'raw exports': 'billing/raw exports',
          'données/rapport_été.md': 'billing/données/rapport_été.md',
          'references/evidence.parquet?download=1#row-4':
              'billing/references/evidence.parquet',
        },
      },
    );
    final bundle = ProjectBundle('knowledge', 'knowledge', temp.path);
    final markdown = KnowledgeProjectSearch(
      [bundle],
      [response],
      limit: 5,
    ).toMarkdown();
    expect(markdown, contains('## Matches'));
    expect(
      markdown,
      contains(
        '### knowledge/billing/invoicing.md:10-20 [knowledge; stable; match]',
      ),
    );
    expect(
      markdown,
      contains(
        '### knowledge/billing/terms.md:1-5 [knowledge; stable; match]\n'
        '- **Relation:** relationship via knowledge/billing/invoicing.md\n\n'
        'Direct match B body.',
      ),
    );
    expect(
      markdown,
      contains(
        '- **Sources:** [S1] captures/pkg/analysis.md#finding-2, '
        '[S2] knowledge/references/revenue.v2.md#table-1, '
        '[S3] knowledge/billing/references/source notes.md, '
        '[S4] knowledge/billing/references/other notes.md, '
        '[S5] knowledge/billing/references/evidence.parquet, '
        '[S6] knowledge/billing/Makefile, '
        '[S7] knowledge/billing/raw exports, '
        '[S8] knowledge/billing/données/rapport_été.md, '
        '[S9] acme.sales, '
        '[S10] all queries in acme.sales, '
        '[S11] extracted PDF/OOXML text, '
        '[S12] //docs.example.test/spec, '
        '[S13] knowledge/billing/references/evidence.parquet?download=1#row-4, '
        '[S14] FY2026/Q1, '
        '[S15] archive/%FF.md, '
        '[S16] /../outside.txt, '
        'https://example.test/spec#s1',
      ),
    );
    expect(markdown, contains('## Related Context'));
    expect(
      markdown,
      contains(
        '### knowledge/billing/oq-12.md:4-9 [knowledge; stable; relationship]',
      ),
    );
    expect(
      markdown,
      contains(
        '- **Relation:** relationship via knowledge/billing/invoicing.md',
      ),
    );
    final json = KnowledgeBundleSearch(bundle, response).toJson();
    final jsonFrontmatter =
        ((((json['matches'] as List).first as Map)['chunk'] as Map)['metadata']
                as Map)['okf']
            as Map;
    expect((jsonFrontmatter['frontmatter'] as Map)['sources'], [
      {'id': 'S1', 'resource': '../../captures/pkg/analysis.md#finding-2'},
      {'id': 'S2', 'resource': '/references/revenue.v2.md#table-1'},
      {'id': 'S3', 'resource': 'references/source notes.md'},
      {'id': 'S4', 'resource': './references/other notes.md'},
      {'id': 'S5', 'resource': 'references/evidence.parquet'},
      {'id': 'S6', 'resource': 'Makefile'},
      {'id': 'S7', 'resource': 'raw exports'},
      {'id': 'S8', 'resource': 'données/rapport_été.md'},
      {'id': 'S9', 'resource': 'acme.sales'},
      {'id': 'S10', 'resource': 'all queries in acme.sales'},
      {'id': 'S11', 'resource': 'extracted PDF/OOXML text'},
      {'id': 'S12', 'resource': '//docs.example.test/spec'},
      {'id': 'S13', 'resource': 'references/evidence.parquet?download=1#row-4'},
      {'id': 'S14', 'resource': 'FY2026/Q1'},
      {'id': 'S15', 'resource': 'archive/%FF.md'},
      {'id': 'S16', 'resource': '/../outside.txt'},
      {'resource': 'https://example.test/spec#s1'},
    ]);
  });

  test('Markdown collapses multiline metadata fields without altering passage '
      'lines', () {
    final hit = SearchResult(
      chunk: Chunk(
        sourcePath: 'guide.md',
        lineStart: 1,
        lineEnd: 2,
        content: 'First line\nSecond line \x1b[31mRed\x1b[0m\tTabbed',
        type: 'paragraph',
        metadata: {
          'okf': {
            'frontmatter': {
              'type': 'Guide\n## Injected Type',
              'title': 'Line 1\n## Related Context\nLine 2\x1b[2J',
              'status': 'stable\n### fake',
            },
            'headingPath': ['Intro\n## Section', 'Sub\r\nHeading'],
          },
        },
      ),
      embedding: null,
      similarity: 0.9,
    );
    final markdown = KnowledgeBundleSearch(
      const ProjectBundle('knowledge', 'knowledge', '/nonexistent'),
      KnowledgeSearchResponse(
        matches: [hit],
        context: [KnowledgeContextHit(hit, 'match')],
        notices: [
          KnowledgeNotice(
            KnowledgeNoticeCode.unresolvedRelationship,
            'Notice line 1\n## Fake Notice Heading',
          ),
        ],
      ),
    ).toMarkdown();
    expect(
      markdown,
      contains(
        '- **Type:** Guide ## Injected Type | '
        r'**Title:** Line 1 ## Related Context Line 2\u{001b}[2J',
      ),
    );
    expect(markdown, contains('- **Section:** Intro ## Section > Sub Heading'));
    expect(
      markdown,
      contains('First line\nSecond line \\u{001b}[31mRed\\u{001b}[0m\tTabbed'),
    );
    expect(markdown, contains('Notice: Notice line 1 ## Fake Notice Heading'));
    expect(markdown, isNot(contains('\n## Related Context\n')));
  });

  test("a matched document's second passage renders after its match", () {
    SearchResult passage(String id, String path, int line, double score) =>
        SearchResult(
          chunk: Chunk(
            id: id,
            sourcePath: path,
            lineStart: line,
            lineEnd: line,
            content: 'Passage $id.',
            type: 'paragraph',
          ),
          embedding: null,
          similarity: score,
        );
    final first = passage('a1', 'a.md', 3, 0.9);
    final response = KnowledgeSearchResponse(
      matches: [first],
      context: [
        KnowledgeContextHit(first, 'match'),
        KnowledgeContextHit(passage('a2', 'a.md', 7, 0.88), 'match'),
        KnowledgeContextHit(
          passage('b1', 'b.md', 1, 0.2),
          'relationship',
          viaPath: 'a.md',
        ),
      ],
      notices: [],
    );
    const bundle = ProjectBundle('knowledge', 'knowledge', '/nonexistent');
    for (final markdown in [
      KnowledgeBundleSearch(bundle, response).toMarkdown(),
      KnowledgeProjectSearch([bundle], [response], limit: 2).toMarkdown(),
    ]) {
      final heading = markdown.indexOf('## Matches');
      final second = markdown.indexOf('Passage a2.');
      final related = markdown.indexOf('## Related Context');
      expect(
        markdown,
        matches(RegExp(r'### (knowledge/)?a\.md:7-7 \[[^\]]*match\]')),
      );
      expect(heading, lessThan(markdown.indexOf('Passage a1.')));
      expect(markdown.indexOf('Passage a1.'), lessThan(second));
      expect(second, lessThan(related));
      expect(related, lessThan(markdown.indexOf('Passage b1.')));
      expect('Passage a2.'.allMatches(markdown), hasLength(1));
    }
  });

  test('fitted fragments of one line render as separate passages', () async {
    final words = [for (var i = 0; i < 40; i++) 'word$i'];
    final fitted =
        await KnowledgeSnapshot.fromSources({
          'long.md': '---\ntype: Guideline\n---\n\n${words.join(' ')}\n',
          'other.md': '---\ntype: Guideline\n---\n\nOther passage.\n',
        }, bundleId: 'fitted').fitInputs(
          countTokens: (text) async => text.split(RegExp(r'\s+')).length,
          maxTokens: 30,
          includeContext: true,
        );
    final fragments = [
      for (final chunk in fitted.chunks)
        if (chunk.sourcePath == 'long.md') chunk,
    ];
    expect(fragments.length, greaterThan(1));
    final [first, second, ...] = fragments;
    expect(
      (second.lineStart, second.lineEnd),
      (first.lineStart, first.lineEnd),
      reason: 'the fragments share a line range',
    );
    final other = fitted.chunks.singleWhere(
      (chunk) => chunk.sourcePath == 'other.md',
    );
    SearchResult hit(Chunk chunk) =>
        SearchResult(chunk: chunk, embedding: null, similarity: 0.5);
    const bundle = ProjectBundle('knowledge', 'knowledge', '/nonexistent');
    for (final response in [
      // The second fragment follows its document's match.
      KnowledgeSearchResponse(
        matches: [hit(first)],
        context: [
          KnowledgeContextHit(hit(first), 'match'),
          KnowledgeContextHit(hit(second), 'match'),
        ],
        notices: [],
      ),
      // Both fragments are related context of another match.
      KnowledgeSearchResponse(
        matches: [hit(other)],
        context: [
          KnowledgeContextHit(hit(other), 'match'),
          for (final fragment in [first, second])
            KnowledgeContextHit(
              hit(fragment),
              'relationship',
              viaPath: 'other.md',
            ),
        ],
        notices: [],
      ),
    ]) {
      final markdown = KnowledgeBundleSearch(bundle, response).toMarkdown();
      for (final fragment in [first, second]) {
        expect(
          fragment.content.trim().allMatches(markdown),
          hasLength(1),
          reason: fragment.id,
        );
      }
    }
  });
}
