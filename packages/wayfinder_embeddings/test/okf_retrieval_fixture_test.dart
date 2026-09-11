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
        final untimedOutput = '${directory.path}/untimed.json';
        await evaluation.main([
          '--stores=memory',
          '--split=$split',
          '--no-timing',
          '--output=$untimedOutput',
        ]);
        final untimed =
            jsonDecode(await File(untimedOutput).readAsString()) as Map;
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
          final untimedRun =
              ((untimed['runs'] as Map)['memory'] as Map)[entry.key] as Map;
          expect(untimedRun['aggregate'], measured['aggregate']);
          expect(untimedRun['groups'], measured['groups']);
          expect(untimedRun['queries'], measured['queries']);
          expect(untimedRun['queryP50Ms'], isNull);
          expect(untimedRun['queryP95Ms'], isNull);
          expect(measured['queryP50Ms'], isNonNegative);
          expect(measured['queryP95Ms'], isNonNegative);
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
