import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
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
      final writer = KnowledgeIndex(store: store, includeContext: true);
      await writer.synchronize(fitted);
      final before = await writer.search('password');
      final reader = KnowledgeIndex.openSnapshot(
        snapshot: restored,
        store: store,
        includeContext: true,
      );
      final after = await reader.search('password');
      expect(
        after.matches.map((hit) => hit.chunk).toList(),
        before.matches.map((hit) => hit.chunk).toList(),
      );
      expect(await store.getAllEmbeddings(), isEmpty);
    },
  );

  test('unknown snapshot version is rejected', () {
    expect(
      () => KnowledgeSnapshot.fromMap({'version': 999}),
      throwsFormatException,
    );
  });
}
