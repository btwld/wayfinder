import 'package:test/test.dart';

import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'support/counting_embedder.dart';

void main() {
  late KnowledgeSnapshot snapshot;
  late KnowledgeIndex index;
  late List<SearchResult> ranked;
  setUp(() {
    String concept(String body) => '---\ntype: Guide\n---\n\n$body\n';
    snapshot = KnowledgeSnapshot.fromSources({
      'policy.md': concept(
        '# Summary\n\nAccess rules need review.\n\n'
        '# Decision\n\nEditors can change records.\n\n'
        '# Background\n\nHistorical review notes.\n\n'
        'See [a](related-a.md) and [b](related-b.md).',
      ),
      'audit.md': concept('Changes leave an audit trail.'),
      'storage.md': concept('Records use durable storage.'),
      'related-a.md': concept('Background context A.'),
      'related-b.md': concept('Background context B.'),
      'governor.md': concept('The governing access policy.'),
    }, bundleId: 'context-regression');
    index = KnowledgeIndex.fromSnapshot(
      snapshot: snapshot,
      store: MemoryStore(),
      embedder: CountingEmbedder(),
    );
    SearchResult hit(String text, double score) => SearchResult(
      chunk: snapshot.chunks.singleWhere((chunk) => chunk.content == text),
      embedding: null,
      similarity: score,
    );
    ranked = [
      hit('Access rules need review.', 0.99),
      hit('Changes leave an audit trail.', 0.98),
      hit('Editors can change records.', 0.97),
      hit('Historical review notes.', 0.96),
      hit('Records use durable storage.', 0.95),
    ];
  });

  test('bounded links cannot crowd out direct and complementary passages', () {
    final result = index.contextForMatches(
      ranked,
      limit: 5,
      policy: KnowledgeSearchPolicy(
        expandRelationships: true,
        maxPassagesPerConcept: 2,
        maxRelationshipPassages: 1,
      ),
    );
    expect(result.context.map((hit) => hit.reason), [
      'match',
      'match',
      'match',
      'match',
      'relationship',
    ]);
    expect(result.context.take(4).map((hit) => hit.result.chunk.content), [
      'Access rules need review.',
      'Changes leave an audit trail.',
      'Editors can change records.',
      'Records use durable storage.',
    ]);
    expect(result.context.last.result.chunk.sourcePath, 'related-a.md');
    for (final hit in result.context) {
      final chunk = hit.result.chunk;
      expect(snapshot.chunks, contains(chunk));
      expect(chunk.lineEnd, greaterThanOrEqualTo(chunk.lineStart));
    }
  });

  test(
    'unused relationship slots return to direct matches and IDs deduplicate',
    () {
      final result = index.contextForMatches(
        [ranked[1], ranked[1], ranked.last],
        limit: 2,
        policy: KnowledgeSearchPolicy(
          expandRelationships: true,
          maxPassagesPerConcept: 2,
          maxRelationshipPassages: 1,
        ),
      );
      expect(result.context.map((hit) => hit.result.chunk.sourcePath), [
        'audit.md',
        'storage.md',
      ]);
      expect(result.context.every((hit) => hit.reason == 'match'), isTrue);
    },
  );

  test('explicit governing evidence still precedes the direct match', () {
    final result = index.contextForMatches(
      ranked,
      limit: 2,
      policy: KnowledgeSearchPolicy(
        maxRelationshipPassages: 0,
        governingSources: {'policy.md': 'governor.md'},
      ),
    );
    expect(result.context.map((hit) => hit.reason), ['governing', 'match']);
    expect(result.context.first.result.chunk.sourcePath, 'governor.md');
  });

  test(
    'one-slot context retains a direct match even with a large link budget',
    () {
      final result = index.contextForMatches(
        ranked,
        limit: 1,
        policy: KnowledgeSearchPolicy(
          expandRelationships: true,
          maxRelationshipPassages: 20,
        ),
      );
      expect(result.context.single.result.chunk.id, ranked.first.chunk.id);
      expect(result.context.single.reason, 'match');
    },
  );

  test('invalid passage limits fail before retrieval', () {
    expect(
      () => KnowledgeSearchPolicy(maxPassagesPerConcept: 0),
      throwsArgumentError,
    );
    expect(
      () => KnowledgeSearchPolicy(maxRelationshipPassages: -1),
      throwsArgumentError,
    );
  });
}
