import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

void main() {
  group('knowledgeBodyLink', () {
    const bundle = 'knowledge';
    const document = 'knowledge/guides/start.md';
    KnowledgeBodyLink link(String href) =>
        knowledgeBodyLink(bundle, document, href);
    String? file(String href) => switch (link(href)) {
      KnowledgeFileLink(:final path) => path,
      _ => null,
    };

    test('a relative path is relative to the document', () {
      expect(file('other.md'), 'knowledge/guides/other.md');
      expect(file('./other.md'), 'knowledge/guides/other.md');
      expect(file('../notes/a.md'), 'knowledge/notes/a.md');
    });

    test('a path starting with a slash is relative to the bundle', () {
      expect(file('/notes/a.md'), 'knowledge/notes/a.md');
    });

    test('a fragment and escapes do not change the file', () {
      expect(file('other.md#a-heading'), 'knowledge/guides/other.md');
      expect(file('my%20notes.md'), 'knowledge/guides/my notes.md');
      expect(file('a%25b.md'), 'knowledge/guides/a%b.md');
      expect(file('a%252Fb.md'), 'knowledge/guides/a%2Fb.md');
      expect(file('%2E%2E/notes/a.md'), 'knowledge/notes/a.md');
    });

    test('an encoded separator, backslash or control character misses', () {
      for (final href in [
        'notes%2Fa.md',
        'notes%2fa.md',
        'sub/a%2Fb.md',
        'a%5Cb.md',
        'a%5cb.md',
        r'a\b.md',
        r'dir\file.md',
        'a%0Ab.md',
        'a%00b.md',
        'a%7Fb.md',
        'a\u0001b.md',
        '%FF.md',
      ]) {
        expect(link(href), isA<KnowledgeOtherLink>(), reason: href);
      }
    });

    test('a link out of the bundle goes nowhere', () {
      expect(link('../../outside.md'), isA<KnowledgeOtherLink>());
      expect(link('../../../../outside.md'), isA<KnowledgeOtherLink>());
      expect(link('../'), isA<KnowledgeOtherLink>());
    });

    test('a bundle at the project root takes every path inside it', () {
      expect(
        knowledgeBodyLink('.', 'guides/start.md', 'a.md'),
        isA<KnowledgeFileLink>().having((l) => l.path, 'path', 'guides/a.md'),
      );
      expect(
        knowledgeBodyLink('.', 'guides/start.md', '/a.md'),
        isA<KnowledgeFileLink>().having((l) => l.path, 'path', 'a.md'),
      );
    });

    test('only http and https with a host are web links', () {
      expect(
        link('https://example.com/a'),
        isA<KnowledgeWebLink>().having(
          (l) => l.uri.host,
          'host',
          'example.com',
        ),
      );
      expect(link('http://example.com'), isA<KnowledgeWebLink>());
      for (final href in [
        'https://',
        'mailto:someone@example.com',
        'file:///etc/passwd',
        'javascript:alert(1)',
        '//example.com/a',
      ]) {
        expect(link(href), isA<KnowledgeOtherLink>(), reason: href);
      }
    });

    test('a bare fragment stays on the page', () {
      expect(link('#a-heading'), isA<KnowledgeAnchorLink>());
    });

    test('an empty or malformed link goes nowhere', () {
      expect(link(''), isA<KnowledgeOtherLink>());
      expect(link('   '), isA<KnowledgeOtherLink>());
      expect(link('%E0%A4%A'), isA<KnowledgeOtherLink>());
    });
  });

  group('parseKnowledgeCitation', () {
    test('a nested bundle keeps its prefix', () {
      final parsed = parseKnowledgeCitation('docs/okf/guides/start.md:3-9');
      expect(parsed, isNotNull);
      expect(parsed!.path, 'docs/okf/guides/start.md');
      expect(parsed.startLine, 3);
      expect(parsed.endLine, 9);
    });

    test('a root bundle citation is just the file path', () {
      final parsed = parseKnowledgeCitation('concepts/start.md:1-5');
      expect(parsed!.path, 'concepts/start.md');
      expect(parsed.startLine, 1);
      expect(parsed.endLine, 5);
    });

    test('deep and spaced paths still parse from the final range', () {
      final parsed = parseKnowledgeCitation(
        'knowledge/my notes/ä guide.md:12-12',
      );
      expect(parsed!.path, 'knowledge/my notes/ä guide.md');
      expect(parsed.startLine, 12);
      expect(parsed.endLine, 12);
    });

    test('malformed citations are rejected, never guessed', () {
      for (final bad in [
        '',
        'concepts/start.md',
        'concepts/start.md:0-3',
        'concepts/start.md:5-3',
        'concepts/start.md:a-b',
      ]) {
        expect(parseKnowledgeCitation(bad), isNull, reason: bad);
      }
    });
  });
}
