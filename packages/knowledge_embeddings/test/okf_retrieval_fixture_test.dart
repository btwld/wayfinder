import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/evaluate_okf_retrieval.dart' as evaluation;

void main() {
  for (final split in ['development', 'held_out']) {
    test(
      'OKF $split BM25 component results preserve passage judgments',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'okf_judgments',
        );
        addTearDown(() => directory.delete(recursive: true));
        final output = '${directory.path}/results.json';
        await evaluation.main([
          '--stores=memory',
          '--split=$split',
          '--output=$output',
        ]);
        final actual = jsonDecode(await File(output).readAsString()) as Map;
        final baseline =
            jsonDecode(
                  await File(
                    'fixtures/benchmarks/okf_ablation_results.json',
                  ).readAsString(),
                )
                as Map;
        final expected = (baseline['splits'] as Map)[split] as Map;
        expect(actual['querySha256'], expected['querySha256']);
        final actualRuns = (actual['runs'] as Map)['memory'] as Map;
        final expectedRuns = (expected['runs'] as Map)['memory'] as Map;
        for (final entry in actualRuns.entries) {
          final measured = entry.value as Map;
          final recorded = expectedRuns[entry.key] as Map;
          expect(
            measured['aggregate'],
            recorded['aggregate'],
            reason: entry.key as String,
          );
          final expectedQueries = {
            for (final row in recorded['queries'] as List)
              (row as Map)['id']: row,
          };
          for (final row in measured['queries'] as List) {
            for (final metric in ['top1', 'recall', 'rr']) {
              expect(
                (row as Map)[metric],
                (expectedQueries[row['id']] as Map)[metric],
                reason: '${entry.key}/${row['id']}/$metric',
              );
            }
          }
        }
      },
    );
  }
}
