import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/knowledge_case_evaluation.dart';
import 'support/counting_embedder.dart';

void main() {
  test('dense case evaluation preserves scopes and vector coverage', () async {
    final fixture = await KnowledgeCases.load();
    final store = MemoryStore();
    addTearDown(store.close);
    final embedder = CountingEmbedder();
    final rows = await fixture.evaluate(store, embedder: embedder);
    expect(rows, hasLength(fixture.cases.length));
    expect(embedder.documents, hasLength(fixture.chunks.length));
    expect(await store.getAllEmbeddings(), hasLength(fixture.chunks.length));
    expect(rows.map((row) => row['mode']).toSet(), {'dense'});
    final chunksById = {for (final chunk in fixture.chunks) chunk.id: chunk};
    for (final row in rows) {
      final source = fixture.cases.singleWhere(
        (item) => item['id'] == row['case'],
      );
      final raw = source['options'] as Map<String, Object?>? ?? const {};
      final options = SearchOptions(
        filePaths: (raw['filePaths'] as List?)?.cast<String>() ?? const [],
        filePatterns:
            (raw['filePatterns'] as List?)?.cast<String>() ?? const [],
        metadataFilters:
            raw['metadataFilters'] as Map<String, Object?>? ?? const {},
      );
      for (final id in row['ids']! as List) {
        expect(
          options.matchesFilters(chunksById[id]!),
          isTrue,
          reason: '${row['case']}/$id',
        );
      }
    }
    // Constant test vectors check mechanics, not relevance quality.
    final noAnswer = rows.singleWhere((row) => row['case'] == 'no_answer');
    expect(noAnswer['top1Relevant'], isNull);
  });
}
