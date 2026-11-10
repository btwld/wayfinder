import 'dart:convert';

import 'package:okf/okf.dart' show OkfDocument;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'support/counting_embedder.dart';

void main() {
  test(
    'source roles preserve navigation/history and parse non-Markdown source keys',
    () {
      final sources = {
        'nested/index.md': '# Index\n\nNavigation-only text.\n',
        'nested/log.md': '# Log\n\nHistory-only text.\n',
        'guide.md': '---\ntype: Guide\ntitle: Guide\n---\nConcept passage.\n',
        'notes.txt': '---\ntype: [\n---\nMalformed source text.\n',
      };
      // Arbitrary fromSources keys are parsed before OKF validates concept paths.
      late final String parseMessage;
      try {
        OkfDocument.parse(sources['notes.txt']!, sourcePath: 'notes.txt');
        fail('The non-Markdown source must still reach the document parser.');
      } on FormatException catch (error) {
        parseMessage = error.message;
      }
      expect(
        () => KnowledgeSnapshot.fromSources(sources, bundleId: 'roles'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'parse failure',
            parseMessage,
          ),
        ),
      );
      sources['notes.txt'] = '---\ntype: Guide\n---\nParsed source text.\n';
      expect(
        () => KnowledgeSnapshot.fromSources(sources, bundleId: 'roles'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'path failure',
            'Concept document paths must end in .md',
          ),
        ),
      );
      sources.remove('notes.txt');
      final snapshot = KnowledgeSnapshot.fromSources(
        sources,
        bundleId: 'roles',
      );
      expect(snapshot.sources, sources);
      expect(snapshot.conceptPaths, {'guide.md'});
      expect(snapshot.chunks.map((c) => c.sourcePath).toSet(), {'guide.md'});
      expect(
        snapshot.chunks.map((c) => c.content).join(),
        contains('Concept passage.'),
      );
      expect(snapshot.assets, isEmpty);
    },
  );

  test(
    'saved token-fitted snapshot retains exact passages, graph and citations',
    () async {
      final original = KnowledgeSnapshot.fromSources({
        'guide.md':
            '---\ntype: reference\ntitle: Recovery\n---\n# Recovery\n\n'
            'Use the recovery email link to reset your password and regain access safely.\n\n'
            'See [related](related.md).',
        'related.md':
            '---\ntype: reference\ntitle: Related\nstatus: draft\n---\nRelated guidance.',
      }, bundleId: 'persisted');
      final fitted = await original.fitInputs(
        countTokens: (text) async => text.split(RegExp(r'\s+')).length,
        maxTokens: 10,
        includeContext: true,
      );
      expect(fitted.chunks.length, greaterThan(original.chunks.length));
      final restored = KnowledgeSnapshot.fromMap(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(fitted.toMap())) as Map,
        ),
      );
      expect(restored.toMap(), fitted.toMap());
      expect(restored.graph.edges.length, fitted.graph.edges.length);
      expect(
        restored.metadataFor('related.md').status,
        fitted.metadataFor('related.md').status,
      );
      final store = MemoryStore();
      addTearDown(store.close);
      final writer = KnowledgeIndex(
        store: store,
        embedder: CountingEmbedder(),
        includeContext: true,
      );
      await writer.synchronize(fitted);
      final before = await writer.search('password');
      final reader = KnowledgeIndex.fromSnapshot(
        snapshot: restored,
        embedder: CountingEmbedder(),
        store: store,
        includeContext: true,
      );
      final after = await reader.search('password');
      expect(
        after.matches.map((hit) => hit.chunk).toList(),
        before.matches.map((hit) => hit.chunk).toList(),
      );
      expect(await store.getAllEmbeddings(), hasLength(fitted.chunks.length));
    },
  );

  test('unknown snapshot version is rejected', () {
    expect(
      () => KnowledgeSnapshot.fromMap({'version': 999}),
      throwsFormatException,
    );
  });
}
