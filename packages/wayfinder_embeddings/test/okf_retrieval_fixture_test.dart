import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

void main() {
  for (final split in ['development', 'held_out']) {
    test('OKF $split judgments refer to current fixture passages', () async {
      final data =
          jsonDecode(
                await File(
                  'fixtures/okf_retrieval/queries.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      final allQueries = (data['queries']! as List)
          .cast<Map<String, Object?>>();
      expect(
        allQueries.map((row) => row['id']).toSet(),
        hasLength(allQueries.length),
      );
      expect(allQueries.map((row) => row['split']).toSet(), {
        'development',
        'held_out',
      });
      final queries = allQueries.where((row) => row['split'] == split).toList();
      expect(queries, isNotEmpty);
      final snapshot = await KnowledgeSnapshot.load(
        'fixtures/okf_retrieval/bundle',
        bundleId: 'fixture-integrity',
      );
      expect(
        snapshot.chunks.map((chunk) => chunk.id).toSet(),
        hasLength(snapshot.chunks.length),
      );
      for (final row in queries) {
        expect(
          row['query'],
          isA<String>().having((text) => text.trim(), 'text', isNotEmpty),
        );
        expect(
          row['group'],
          isA<String>().having((text) => text.trim(), 'group', isNotEmpty),
        );
        for (final support
            in (row['support']! as List).cast<Map<String, Object?>>()) {
          expect(
            snapshot.chunks.any(
              (chunk) =>
                  chunk.sourcePath == support['path'] &&
                  chunk.content.contains(support['contains']! as String),
            ),
            isTrue,
            reason: '${row['id']}: $support',
          );
        }
      }
      // Relevance scoring uses the genuine native dense CI gate, not test vectors.
    });
  }
}
