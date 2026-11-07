import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

void main() {
  test('knowledgeCount uses the plural unless the count is one', () {
    expect(knowledgeCount(0, 'concept'), '0 concepts');
    expect(knowledgeCount(1, 'concept'), '1 concept');
    expect(knowledgeCount(2, 'concept'), '2 concepts');
    expect(knowledgeCount(2, 'index', 'indexes'), '2 indexes');
  });

  test('knowledgeHumanize turns a name into capitalised words', () {
    expect(knowledgeHumanize('depends-on'), 'Depends on');
    expect(knowledgeHumanize('in_text_link'), 'In text link');
    expect(knowledgeHumanize('--'), '');
  });

  test('dates read in the local time zone', () {
    final morning = DateTime(2026, 8, 26, 9, 5);
    expect(knowledgeDate(morning), '26 Aug 2026');
    expect(knowledgeDateTime(morning), '26 Aug 2026, 09:05');
    expect(knowledgeDate(DateTime(2026, 1, 1)), '1 Jan 2026');
    expect(knowledgeDate(DateTime(2026, 12, 31)), '31 Dec 2026');
  });

  group('knowledgeResourceLabel', () {
    test('a Git pin shows its short commit and the file name', () {
      expect(
        knowledgeResourceLabel('git:3023A6Dabcdef:docs/guide.md'),
        'git · 3023a6d · guide.md',
      );
      expect(knowledgeResourceLabel('git:3023a6d'), 'git · 3023a6d');
      expect(knowledgeResourceLabel('git:3023a6d:'), 'git · 3023a6d');
    });

    test('anything else is returned as written', () {
      for (final resource in [
        'https://example.com/a',
        'git:xyz',
        'git:3023a6',
      ]) {
        expect(knowledgeResourceLabel(resource), resource);
      }
    });

    test('isKnowledgeGitResource tells a pin from anything else', () {
      expect(isKnowledgeGitResource(' git:3023a6d:a.md '), isTrue);
      expect(isKnowledgeGitResource('https://example.com'), isFalse);
    });
  });
}
