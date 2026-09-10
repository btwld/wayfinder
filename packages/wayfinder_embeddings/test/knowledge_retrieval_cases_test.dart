import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/knowledge_case_evaluation.dart';

void main() {
  test(
    'lexical knowledge cases honor explicit scopes without embeddings',
    () async {
      final fixture = await KnowledgeCases.load();
      final store = MemoryStore();
      addTearDown(store.close);
      final rows = await fixture.evaluate(store);
      expect(rows, hasLength(13));
      expect(await store.getAllEmbeddings(), isEmpty);
      for (final id in [
        'exact_symbol',
        'current_recovery',
        'historical_recovery',
        'authority_scoped',
        'scope_server',
        'scope_browser',
        'freshness_scoped',
        'missing_trust',
      ]) {
        expect(
          rows.singleWhere((row) => row['case'] == id)['top1Relevant'],
          isTrue,
          reason: id,
        );
      }
      // Shared ordinary words still produce lexical candidates for an
      // unanswerable question. Retrieval is not an answerability check.
      final noAnswer = rows.singleWhere((row) => row['case'] == 'no_answer');
      expect(noAnswer['ids'], isNotEmpty);
      expect(noAnswer['top1Relevant'], isNull);
    },
  );
}
