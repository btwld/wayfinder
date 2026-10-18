import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

const header = '---\ntype: Reference\ntitle: Workflow\n---\n';
Future<int> words(String text) async => text.split(RegExp(r'\s+')).length;

KnowledgeSnapshot parse(String body, {bool grouped = true}) =>
    KnowledgeSnapshot.fromSources(
      {'guide.md': '$header$body'},
      bundleId: 'synthetic',
      groupSections: grouped,
    );

void main() {
  test('literal trailing hash in a heading is not a closing marker', () {
    final snapshot = parse(
      '### C#\n\nLanguage guide.\n\n### Next ###\n\nMore.',
    );
    expect(
      snapshot.textFor(snapshot.chunks.first, includeContext: true),
      contains('Section: C#'),
    );
    expect(
      snapshot.textFor(snapshot.chunks.last, includeContext: true),
      contains('Section: Next\n'),
    );
  });

  test('groups a labelled message without mixing request and response', () {
    final snapshot = parse(
      '# Thread\n\n'
      '**Morgan (Reviewer), May 3, 10:20:**\n\n'
      'Please reply with this confirmation.\n\n'
      '"I approve the proposal with the changes applied."\n\n'
      '**Riley (Owner), May 3, 10:22:**\n\n'
      'Hello Morgan.\n\nI approve the proposal with the changes applied.\n',
    );
    expect(snapshot.chunks, hasLength(2));
    expect(snapshot.chunks.first.content, contains('Please reply'));
    expect(snapshot.chunks.last.content, startsWith('**Riley'));
    expect(snapshot.chunks.last.content, isNot(contains('Please reply')));
    expect(snapshot.chunks.map((c) => c.lineStart), [7, 13]);
    for (final chunk in snapshot.chunks) {
      final lines = snapshot.sources['guide.md']!.split('\n');
      expect(
        chunk.content,
        lines.sublist(chunk.lineStart - 1, chunk.lineEnd).join('\n'),
      );
    }
  });

  test('headings, subheadings, transcript turns and events stay separate', () {
    final snapshot = parse(
      'Overview\n========\n\nFirst point.\n\nSecond point.\n\n'
      '## Review\n\nMorgan Smith   01:23First turn.\n\n'
      'More of the same turn.\n\nRiley Lee   01:24Second turn.\n\n'
      '**Task completed — May 3, 10:25.**\n\n'
      '## Next\n\nAnother subject.',
    );
    expect(snapshot.chunks, hasLength(5));
    expect(snapshot.chunks.first.content, 'First point.\n\nSecond point.');
    expect(snapshot.chunks[1].content, contains('More of the same turn.'));
    expect(snapshot.chunks[2].content, isNot(contains('Morgan')));
    expect(snapshot.chunks.last.metadata['blockLabel'], isNull);
    expect(
      snapshot.textFor(snapshot.chunks.first, includeContext: true),
      contains('Section: Overview'),
    );
  });

  test(
    'complete units can exceed soft target without unnecessary splits',
    () async {
      final snapshot = parse(
        '# Policy\n\n'
        'The rule applies when the request is valid.\n\n'
        'Exception: an expired request must go through review.',
      );
      final fitted = await snapshot.fitInputs(
        countTokens: words,
        targetTokens: 12,
        maxTokens: 40,
        includeContext: true,
      );
      expect(fitted.chunks, hasLength(1));
      expect(fitted.chunks.single.content, contains('Exception:'));
    },
  );

  test(
    'oversized units preserve every byte and attribution under token cap',
    () async {
      final snapshot = parse(
        '# Discussion\n\n**Morgan, May 3:**\n\n'
        '${List.generate(8, (i) => 'Point $i describes the condition. The exception is also recorded.').join('\n\n')}',
      );
      final original = snapshot.chunks.single;
      final fitted = await snapshot.fitInputs(
        countTokens: words,
        targetTokens: 34,
        maxTokens: 46,
        includeContext: true,
      );
      expect(fitted.chunks.length, greaterThan(1));
      expect(fitted.chunks.map((c) => c.content).join(), original.content);
      for (final chunk in fitted.chunks) {
        final input = fitted.textFor(chunk, includeContext: true);
        expect(await words(input), lessThanOrEqualTo(46));
        expect(input, contains('Source label: **Morgan, May 3:**'));
      }
      final reopened = KnowledgeSnapshot.fromMap(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(fitted.toMap())) as Map,
        ),
      );
      expect(reopened.toMap(), fitted.toMap());
      final refit = await reopened.fitInputs(
        countTokens: words,
        targetTokens: 34,
        maxTokens: 46,
        includeContext: true,
      );
      expect(refit.toMap(), fitted.toMap());
    },
  );

  test('table splits retain columns and surrounding source label', () async {
    final snapshot = parse(
      '# Results\n\n**Morgan, May 3:**\n\nSummary.\n\n'
      '| Item | Value |\n| --- | --- |\n'
      '${List.generate(12, (i) => '| row$i | observed value $i |').join('\n')}\n\n'
      'These are separate examples, not one event sequence.',
    );
    final fitted = await snapshot.fitInputs(
      countTokens: words,
      targetTokens: 36,
      maxTokens: 50,
      includeContext: true,
    );
    final tables = fitted.chunks.where((c) => c.type == 'table');
    expect(tables.length, greaterThan(1));
    expect(
      tables.map((c) => c.content).join(),
      snapshot.chunks.singleWhere((c) => c.type == 'table').content,
    );
    for (final chunk in tables) {
      final input = fitted.textFor(chunk, includeContext: true);
      expect(input, contains('Table columns: | Item | Value |'));
      expect(input, contains('Source label: **Morgan, May 3:**'));
      expect(await words(input), lessThanOrEqualTo(50));
    }
    expect(
      fitted.textFor(fitted.chunks.last, includeContext: true),
      contains('Source label: **Morgan, May 3:**'),
    );
  });

  test('fences hide headings, labels, and setext-like lines', () {
    final snapshot = parse(
      '# Example\n\n```text\n---\n'
      '# not a heading\n**not a speaker:**\n```\n\nReal prose.',
    );
    expect(snapshot.chunks, hasLength(2));
    expect(snapshot.chunks.first.type, 'code');
    expect(snapshot.chunks.first.content, contains('**not a speaker:**'));
    expect(snapshot.chunks.last.metadata['blockLabel'], isNull);
  });

  test('legacy paragraph defaults and apparatus fallback remain available', () {
    expect(
      parse('# Heading\n\nOne.\n\nTwo.', grouped: false).chunks,
      hasLength(2),
    );
    expect(parse('# Heading\n\nOne.\n\nTwo.').chunks, hasLength(1));
    expect(parse('# Heading only').chunks.single.type, 'heading');
    expect(
      parse(
        '---\n\n# Heading\n\nBody.\n\n[^x]: citation.',
      ).chunks.any((c) => c.type == 'footnote'),
      isFalse,
    );
  });

  test(
    'oversized tokens keep Unicode and reject invalid size policy',
    () async {
      final snapshot = parse('# Example\n\n${'😀' * 200}');
      final fitted = await snapshot.fitInputs(
        countTokens: (s) async => s.runes.length,
        targetTokens: 30,
        maxTokens: 60,
        includeContext: false,
      );
      expect(
        fitted.chunks.map((c) => c.content).join(),
        snapshot.chunks.single.content,
      );
      expect(fitted.chunks.every((c) => !c.content.contains('\uFFFD')), isTrue);
      expect(
        snapshot.fitInputs(
          countTokens: words,
          targetTokens: 61,
          maxTokens: 60,
          includeContext: false,
        ),
        throwsArgumentError,
      );
    },
  );
}
