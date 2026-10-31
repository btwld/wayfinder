import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

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
        '[S15] knowledge/billing/archive/%FF.md, '
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
}
