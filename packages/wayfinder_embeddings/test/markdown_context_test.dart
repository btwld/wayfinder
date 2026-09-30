import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

KnowledgeSnapshot snapshot(
  String body, {
  String description = 'Layout guide',
}) => KnowledgeSnapshot.fromSources({
  'guide.md':
      '''---
type: reference
title: Flutter
description: $description
tags: [private-tag]
status: draft
custom: provenance-secret
---
# Layout
## Constraints
### Examples
$body''',
}, bundleId: 'context');

void main() {
  test(
    'selective frontmatter and complete heading context preserve identity',
    () {
      final original = snapshot('Useful paragraph.');
      final chunk = original.chunks.single;
      final input = original.textFor(chunk, includeContext: true);
      expect(input, contains('Title: Flutter'));
      expect(input, contains('Description: Layout guide'));
      expect(input, contains('Section: Layout > Constraints > Examples'));
      for (final excluded in ['private-tag', 'draft', 'provenance-secret']) {
        expect(input, isNot(contains(excluded)));
      }
      expect(
        original.textFor(chunk, includeContext: false),
        'Useful paragraph.',
      );
      final changed = snapshot('Useful paragraph.', description: 'New summary');
      expect(changed.chunks.single.id, chunk.id);
      expect(changed.chunks.single.lineStart, chunk.lineStart);
      expect(
        changed.textFor(changed.chunks.single, includeContext: true),
        contains('Description: New summary'),
      );
      final oversized = snapshot('Useful paragraph.', description: 'x' * 241);
      expect(
        oversized.textFor(oversized.chunks.single, includeContext: true),
        isNot(contains('Description:')),
      );
    },
  );

  test('long and tilde fences preserve nested fence lines and language', () {
    for (final fence in ['````', '~~~~']) {
      final body = '$fence dart\n```\n# literal heading\n```\n$fence';
      final parsed = snapshot(body);
      final chunk = parsed.chunks.single;
      expect(chunk.type, 'code');
      expect(chunk.content, body);
      expect(chunk.metadata['codeLanguage'], 'dart');
      expect(
        parsed.textFor(chunk, includeContext: true),
        contains('Code language: dart'),
      );
    }
  });

  for (final type in ['table', 'code']) {
    test('$type fragments retain context, source text, and citations', () async {
      final body = type == 'table'
          ? '| API | Behavior |\n| --- | --- |\n${List.generate(30, (i) => '| Row$i | Value$i |').join('\n')}'
          : '```dart\n${List.generate(30, (i) => 'final value$i = $i;').join('\n')}\n```';
      final original = snapshot(body);
      final parent = original.chunks.single;
      final fitted = await original.fitInputs(
        countTokens: (text) async => text.runes.length,
        maxTokens: 240,
        includeContext: true,
      );
      expect(fitted.chunks.length, greaterThan(1));
      expect(fitted.chunks.map((c) => c.content).join(), parent.content);
      var offset = 0;
      for (final chunk in fitted.chunks) {
        final input = fitted.textFor(chunk, includeContext: true);
        expect(input.runes.length, lessThanOrEqualTo(240));
        expect(input, contains('Section: Layout > Constraints > Examples'));
        expect(
          input,
          contains(
            type == 'table'
                ? 'Table columns: | API | Behavior |\n| --- | --- |'
                : 'Code language: dart',
          ),
        );
        expect(
          chunk.lineStart,
          parent.lineStart +
              '\n'.allMatches(parent.content.substring(0, offset)).length,
        );
        offset += chunk.content.length;
      }
      final reopened = KnowledgeSnapshot.fromMap(fitted.toMap());
      expect(reopened.chunks, fitted.chunks);
      for (final chunk in reopened.chunks) {
        expect(
          reopened.textFor(chunk, includeContext: true),
          fitted.textFor(chunk, includeContext: true),
        );
      }
    });
  }
}
