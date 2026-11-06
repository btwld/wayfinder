import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

KnowledgeConceptSummary _concept(
  String title, {
  String? id,
  List<String> tags = const [],
}) => KnowledgeConceptSummary(
  bundle: 'knowledge',
  id: id ?? 'x/${title.toLowerCase().replaceAll(' ', '-')}',
  path: 'knowledge/$title.md',
  title: title,
  type: 'Guide',
  tags: tags,
);

void main() {
  final concepts = [
    _concept('Repayments', id: 'x/repay'),
    _concept('Late payment fees', id: 'x/late'),
    _concept('Onboarding', tags: const ['payment']),
    _concept('Payment terms', id: 'x/terms'),
    _concept('Payment', id: 'x/exact'),
    _concept('Glossary'),
  ];

  List<String> titles(List<KnowledgeTitleMatch> matches) => [
    for (final match in matches) match.concept.title,
  ];

  group('knowledgeTitleMatches', () {
    test('ranks an exact title, a prefix, a word, then the rest', () {
      expect(titles(knowledgeTitleMatches(concepts, 'payment')), [
        'Payment',
        'Payment terms',
        'Late payment fees',
        'Onboarding',
        'Repayments',
      ]);
    });

    test('ignores case and surrounding space', () {
      expect(titles(knowledgeTitleMatches(concepts, '  GLOSSARY ')), [
        'Glossary',
      ]);
    });

    test('an empty query matches nothing', () {
      expect(knowledgeTitleMatches(concepts, '   '), isEmpty);
    });

    test('limit keeps the best matches', () {
      expect(titles(knowledgeTitleMatches(concepts, 'payment', limit: 2)), [
        'Payment',
        'Payment terms',
      ]);
    });

    for (final query in ['foo bar', 'foo bar baz']) {
      test('whole-title matches outrank per-word matches for "$query"', () {
        final candidates = [
          _concept('foo', tags: query.split(' ').skip(1).toList()),
          _concept('foo', id: 'bar-baz'),
          _concept('$query guide'),
          _concept(query),
        ];
        final matches = knowledgeTitleMatches(candidates, query);
        expect(matches.map((match) => match.concept), [
          candidates[3],
          candidates[2],
          candidates[0],
          candidates[1],
        ]);
        expect(matches.first.score, greaterThan(matches[2].score));
        expect(matches[2].titleRanges, [(start: 0, end: 3)]);
        expect(
          knowledgeTitleMatches(candidates, query, limit: 1).single.concept,
          same(candidates[3]),
        );
      });
    }

    test('marks the matched part of the title', () {
      final match = knowledgeTitleMatches(
        concepts,
        'payment',
      ).firstWhere((match) => match.concept.title == 'Late payment fees');
      expect(match.titleRanges, [(start: 5, end: 12)]);
    });

    test('a tag or id match marks nothing in the title', () {
      final match = knowledgeTitleMatches(
        concepts,
        'payment',
      ).firstWhere((match) => match.concept.title == 'Onboarding');
      expect(match.titleRanges, isEmpty);
    });

    test('every word of the query must match somewhere', () {
      final matches = knowledgeTitleMatches(concepts, 'terms pay');
      expect(titles(matches), ['Payment terms']);
      expect(matches.single.titleRanges, [
        (start: 0, end: 3),
        (start: 8, end: 13),
      ]);
      expect(knowledgeTitleMatches(concepts, 'terms zebra'), isEmpty);
    });

    test('letters in order match a title, unless too scattered', () {
      final matches = knowledgeTitleMatches(concepts, 'pmt');
      expect(titles(matches), contains('Payment terms'));
      expect(knowledgeTitleMatches(concepts, 'zzz'), isEmpty);
    });
  });

  group('knowledgeQueryRanges', () {
    test('finds every word of two letters or more, any case', () {
      expect(knowledgeQueryRanges('The Payment and payment', 'PAYMENT a'), [
        (start: 4, end: 11),
        (start: 16, end: 23),
      ]);
    });

    test('merges overlapping words', () {
      expect(knowledgeQueryRanges('payment', 'pay payment'), [
        (start: 0, end: 7),
      ]);
    });
  });

  group('knowledgeSnippet', () {
    test('a short passage is only flattened', () {
      expect(knowledgeSnippet('one\n  two', 'two'), 'one two');
    });

    test('a long passage is cut around its first match, on word ends', () {
      final text = '${'word ' * 100}needle ${'word ' * 100}';
      final snippet = knowledgeSnippet(text, 'needle', length: 60);
      expect(snippet, contains('needle'));
      expect(snippet, startsWith('…word'));
      expect(snippet, endsWith('word…'));
      expect(snippet.length, lessThanOrEqualTo(62));
    });

    for (final (boundary, text) in [
      ('start', '${'x' * 300}needle ${'tail ' * 100}'),
      ('end', '${'word ' * 100}${'x' * 20}needle${'x' * 300} ${'tail ' * 100}'),
    ]) {
      test('$boundary boundary keeps a match inside an unbroken token', () {
        final snippet = knowledgeSnippet(text, 'needle');
        expect(snippet, contains('needle'));
        expect(snippet, startsWith('…'));
        expect(snippet, endsWith('…'));
        expect(snippet.length, lessThanOrEqualTo(222));
      });
    }

    test('with no match, the passage is cut from its start', () {
      final snippet = knowledgeSnippet('word ' * 100, 'absent', length: 60);
      expect(snippet, startsWith('word'));
      expect(snippet, endsWith('…'));
    });
  });
}
