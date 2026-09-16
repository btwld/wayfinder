import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

Future<int> count(String text) async => text.runes.length + 2;

KnowledgeSnapshot source(String body, {String title = 'Guide'}) =>
    KnowledgeSnapshot.fromSources(
      {'guide.md': '---\ntype: reference\ntitle: $title\n---\n$body'},
      bundleId: 'fitting',
      maxChunkLength: 10000,
    );

KnowledgeSnapshot reopen(KnowledgeSnapshot snapshot) =>
    KnowledgeSnapshot.fromMap(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(snapshot.toMap())) as Map,
      ),
    );

void checkPassages(KnowledgeSnapshot original, KnowledgeSnapshot fitted) {
  expect(fitted.sources, original.sources);
  for (final parent in original.chunks) {
    final fragments = fitted.chunks.where(
      (c) =>
          c.id == parent.id ||
          (c.metadata['okf']! as Map)['parentChunkId'] == parent.id,
    );
    expect(fragments.map((c) => c.content).join(), parent.content);
    var offset = 0;
    for (final fragment in fragments) {
      expect(
        fragment.content,
        parent.content.substring(offset, offset + fragment.content.length),
      );
      expect(
        fragment.lineStart,
        parent.lineStart +
            '\n'.allMatches(parent.content.substring(0, offset)).length,
      );
      expect(
        fragment.lineEnd,
        fragment.lineStart +
            '\n'.allMatches(fragment.content.trimRight()).length,
      );
      expect(utf8.decode(utf8.encode(fragment.content)), fragment.content);
      if (fragment.id != parent.id) {
        final metadata = fragment.metadata['okf']! as Map;
        expect(
          fragment.id,
          sha256
              .convert(
                utf8.encode(
                  jsonEncode([
                    parent.id,
                    offset,
                    offset + fragment.content.length,
                  ]),
                ),
              )
              .toString(),
        );
        expect(metadata['characterStart'], offset);
        expect(metadata['characterEnd'], offset + fragment.content.length);
      }
      offset += fragment.content.length;
    }
  }
}

void main() {
  group('whitespace stays attached to nonblank passages', () {
    Future<int> whitespaceInsensitiveCount(String text) async =>
        text.replaceAll(RegExp(r'\s'), '').runes.length + 2;

    for (final (label, body) in [
      ('indented separator', '  ${'-' * 700} end.'),
      ('padded Unicode', '${' ' * 100}${'😀' * 80}${'\t' * 100}'),
      ('indented prose', '${' ' * 4000}${'hello ' * 100}'),
    ]) {
      for (final context in [false, true]) {
        test('$label with includeContext=$context', () async {
          final original = source(body, title: 'prefix' * 60);
          final fitted = await original.fitInputs(
            countTokens: whitespaceInsensitiveCount,
            maxTokens: 32,
            includeContext: context,
          );

          checkPassages(original, fitted);
          for (final chunk in fitted.chunks) {
            final input = fitted.textFor(chunk, includeContext: true);
            expect(input.trim(), isNotEmpty);
            expect(
              await whitespaceInsensitiveCount(input),
              lessThanOrEqualTo(32),
            );
          }
          expect(
            fitted.diagnostics.any(
              (d) => d.code == 'embedding_context_omitted',
            ),
            context,
          );
          expect(
            (await reopen(fitted).fitInputs(
              countTokens: whitespaceInsensitiveCount,
              maxTokens: 32,
              includeContext: context,
            )).toMap(),
            fitted.toMap(),
          );
        });
      }
    }

    test('retained whitespace still counts against the token budget', () async {
      final original = source('  😀  ');
      await expectLater(
        original.fitInputs(
          countTokens: count,
          maxTokens: 4,
          includeContext: false,
        ),
        throwsStateError,
      );
    });
  });

  test(
    'multiple runs, code/table passages, Unicode and whitespace are lossless',
    () async {
      final original = source(
        '  lead ${'😀' * 37} ${'identifier' * 30}\n'
        'tail ${'-' * 700}  \n\n'
        '```text\n  ${'x' * 180}\n  trailing  \n```\n\n'
        '| Value |\n| --- |\n| ${'z' * 180} |',
      );
      final fitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 40,
        includeContext: false,
      );
      checkPassages(original, fitted);
      for (final c in fitted.chunks) {
        expect(
          await count(fitted.textFor(c, includeContext: true)),
          lessThanOrEqualTo(40),
        );
      }
      expect(fitted.diagnostics.single.code, 'oversized_segment_split');
      expect(fitted.diagnostics.single.affectedChunks, original.chunks.length);
      final again = await original.fitInputs(
        countTokens: count,
        maxTokens: 40,
        includeContext: false,
      );
      expect(again.toMap(), fitted.toMap());
      expect(() => fitted.diagnostics.clear(), throwsUnsupportedError);
    },
  );

  test('nonmonotone tokenizer measures every emitted complete input', () async {
    final original = source('alpha beta gamma delta epsilon ${'😀' * 20}');
    Future<int> nonmonotone(String text) async =>
        text.runes.length == 12 ? 1 : text.runes.length + 2;
    final fitted = await original.fitInputs(
      countTokens: nonmonotone,
      maxTokens: 14,
      includeContext: true,
    );
    checkPassages(original, fitted);
    for (final c in fitted.chunks) {
      expect(
        await nonmonotone(fitted.textFor(c, includeContext: true)),
        lessThanOrEqualTo(14),
      );
    }
  });

  test(
    'context retry rolls back provisional fragments and split warnings',
    () async {
      final original = source('abcdefghi Z', title: 'Prefix');
      final measured = <String>[];
      Future<int> selective(String text) async {
        measured.add(text);
        if (!text.startsWith('Prefix\n\n')) return 1;
        if (text.endsWith('Z')) return 100;
        return text.length;
      }

      final fitted = await original.fitInputs(
        countTokens: selective,
        maxTokens: 12,
        includeContext: true,
      );
      expect(measured, contains('Prefix\n\nZ'));
      expect(fitted.chunks.single.id, original.chunks.single.id);
      expect(
        fitted.textFor(fitted.chunks.single, includeContext: true),
        'abcdefghi Z',
      );
      expect(fitted.diagnostics.map((d) => d.code), [
        'embedding_context_omitted',
      ]);
      expect(fitted.metadataFor('guide.md').raw['title'], 'Prefix');
      expect(
        (await reopen(fitted).fitInputs(
          countTokens: selective,
          maxTokens: 12,
          includeContext: true,
        )).toMap(),
        fitted.toMap(),
      );
    },
  );

  test(
    'durable diagnostics count originals, not fragments or refitting attempts',
    () async {
      final original = KnowledgeSnapshot.fromSources(
        {
          'z.md':
              '---\ntitle: ${'huge' * 40}\n---\n${'x' * 120}\n\n${'y' * 120}',
          'a.md': '---\ntitle: Short\n---\n${'z' * 120}',
        },
        bundleId: 'aggregate',
        maxChunkLength: 10000,
      );
      final fitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 32,
        includeContext: true,
      );
      expect(
        fitted.diagnostics.map(
          (d) => '${d.sourcePath}/${d.code}/${d.affectedChunks}',
        ),
        [
          'a.md/oversized_segment_split/1',
          'z.md/embedding_context_omitted/2',
          'z.md/oversized_segment_split/2',
        ],
      );
      for (final d in fitted.diagnostics.where((d) => d.sourcePath == 'z.md')) {
        final parents = original.chunks.where((c) => c.sourcePath == 'z.md');
        expect(d.lineStart, parents.first.lineStart);
        expect(d.lineEnd, parents.last.lineEnd);
      }
      final saved = reopen(fitted);
      expect(saved.toMap(), fitted.toMap());
      final same = await saved.fitInputs(
        countTokens: count,
        maxTokens: 32,
        includeContext: true,
      );
      expect(same.toMap(), fitted.toMap());
      final tighter = await saved.fitInputs(
        countTokens: count,
        maxTokens: 16,
        includeContext: true,
      );
      checkPassages(original, tighter);
      expect(
        tighter.diagnostics.map((d) => d.toJson()),
        fitted.diagnostics.map((d) => d.toJson()),
      );
      final legacy = original.toMap()..remove('inputRecoveries');
      expect(KnowledgeSnapshot.fromMap(legacy).diagnostics, isEmpty);
    },
  );

  test('reopened context failure retries the complete original body', () async {
    final original = source('one two three four five six');
    final first = await original.fitInputs(
      countTokens: count,
      maxTokens: 20,
      includeContext: true,
    );
    expect(first.chunks.length, greaterThan(1));
    Future<int> selective(String text) async =>
        text.startsWith('Guide\n\n') ? 100 : 1;
    final retried = await reopen(
      first,
    ).fitInputs(countTokens: selective, maxTokens: 10, includeContext: true);
    expect(retried.chunks.single.id, original.chunks.single.id);
    expect(retried.chunks.single.content, original.chunks.single.content);
    expect(
      retried.textFor(retried.chunks.single, includeContext: true),
      original.chunks.single.content,
    );
    expect(retried.diagnostics.single.code, 'embedding_context_omitted');
  });

  test(
    'whitespace splitting is silent and fitting fast path retains IDs',
    () async {
      final original = source('one two three four five six seven eight');
      final fitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 15,
        includeContext: false,
      );
      expect(fitted.diagnostics, isEmpty);
      checkPassages(original, fitted);
      final fast = await original.fitInputs(
        countTokens: count,
        maxTokens: 100,
        includeContext: true,
      );
      expect(fast.toMap(), original.toMap());
    },
  );

  test(
    'invalid budgets, body-only failures and tokenizer errors propagate',
    () async {
      final original = source('😀x');
      for (final budget in [0, -1]) {
        await expectLater(
          original.fitInputs(
            countTokens: count,
            maxTokens: budget,
            includeContext: true,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        original.fitInputs(
          countTokens: count,
          maxTokens: 2,
          includeContext: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('body-only'), contains('guide.md'), contains('2')),
          ),
        ),
      );
      final failure = StateError('tokenizer failed');
      var calls = 0;
      await expectLater(
        original.fitInputs(
          countTokens: (_) async {
            calls++;
            throw failure;
          },
          maxTokens: 10,
          includeContext: true,
        ),
        throwsA(same(failure)),
      );
      expect(calls, 1);
      final fitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 3,
        includeContext: false,
      );
      expect(fitted.chunks.map((c) => c.content), ['😀', 'x']);
      expect(fitted.diagnostics.map((d) => d.code), [
        'oversized_segment_split',
      ]);
    },
  );
}
