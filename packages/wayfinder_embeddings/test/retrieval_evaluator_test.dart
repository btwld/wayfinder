import 'dart:convert';
import 'dart:math' as math;

import 'package:test/test.dart';

import '../tool/src/retrieval_evaluator.dart';

void main() {
  group('RetrievalEvaluator', () {
    test('computes recall, nDCG, and reciprocal rank at k', () {
      final judgments = RelevanceJudgments.fromMap({
        'encrypt data': {'chunk-a': 3, 'chunk-b': 2, 'chunk-c': 0},
      });

      final evaluation = RetrievalEvaluator.evaluate(
        judgments: judgments,
        rankedChunkIdsByQuery: {
          'encrypt data': ['chunk-b', 'chunk-a', 'chunk-z'],
        },
        k: 3,
      );

      final queryMetrics = evaluation.queries.single;
      final expectedDcg = 2 / _log2(2) + 3 / _log2(3);
      final expectedIdeal = 3 / _log2(2) + 2 / _log2(3);

      expect(queryMetrics.metrics.recall, 1.0);
      expect(
        queryMetrics.metrics.ndcg,
        closeTo(expectedDcg / expectedIdeal, 1e-9),
      );
      expect(queryMetrics.metrics.mrr, 1.0);
      expect(evaluation.average.recall, queryMetrics.metrics.recall);
      expect(evaluation.average.ndcg, queryMetrics.metrics.ndcg);
      expect(evaluation.average.mrr, queryMetrics.metrics.mrr);
    });

    test('scores missing result lists as zero without dropping the query', () {
      final judgments = RelevanceJudgments.fromMap({
        'refresh token': {'chunk-a': 3},
      });

      final evaluation = RetrievalEvaluator.evaluate(
        judgments: judgments,
        rankedChunkIdsByQuery: const {},
        k: 10,
      );

      expect(evaluation.queryCount, 1);
      expect(evaluation.average.recall, 0);
      expect(evaluation.average.ndcg, 0);
      expect(evaluation.average.mrr, 0);
    });

    test('does not count duplicate ranked ids as repeated relevant hits', () {
      final judgments = RelevanceJudgments.fromMap({
        'refresh token': {'chunk-a': 3},
      });

      final evaluation = RetrievalEvaluator.evaluate(
        judgments: judgments,
        rankedChunkIdsByQuery: const {
          'refresh token': ['chunk-a', 'chunk-a'],
        },
        k: 2,
      );

      final queryEvaluation = evaluation.queries.single;
      expect(queryEvaluation.metrics.recall, 1);
      expect(queryEvaluation.metrics.ndcg, 1);
      expect(queryEvaluation.metrics.mrr, 1);
      expect(queryEvaluation.retrievedRelevantChunkIds, ['chunk-a']);
    });

    test('rejects malformed relevance judgments', () {
      expect(
        () => RelevanceJudgments(relevanceByQuery: const {}),
        throwsArgumentError,
      );
      expect(
        () => RelevanceJudgments(
          relevanceByQuery: {
            '': {'chunk-a': 1},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => RelevanceJudgments(relevanceByQuery: {'q1': const {}}),
        throwsArgumentError,
      );
      expect(
        () => RelevanceJudgments(
          relevanceByQuery: {
            'q1': {'': 1},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => RelevanceJudgments(
          relevanceByQuery: {
            'q1': {'chunk-a': -1},
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid relevance grades', () {
      expect(
        () => RelevanceJudgments.fromMap({
          'bad': {'chunk-a': -1},
        }),
        throwsFormatException,
      );
    });

    test('rejects blank serialized qrels ids with a format error', () {
      expect(
        () => RelevanceJudgments.fromMap({
          ' ': {'chunk-a': 1},
        }),
        throwsFormatException,
      );
      expect(
        () => RelevanceJudgments.fromMap({
          'q1': {' ': 1},
        }),
        throwsFormatException,
      );
    });

    test('rejects empty serialized qrels maps with a format error', () {
      expect(() => RelevanceJudgments.fromMap(const {}), throwsFormatException);
      expect(
        () => RelevanceJudgments.fromMap({'q1': const {}}),
        throwsFormatException,
      );
    });

    test('rejects invalid retrieval metric values', () {
      expect(
        () => RetrievalMetrics(k: 0, recall: 0.8, ndcg: 0.7, mrr: 0.6),
        throwsArgumentError,
      );
      expect(
        () => RetrievalMetrics(k: 10, recall: -0.1, ndcg: 0.7, mrr: 0.6),
        throwsArgumentError,
      );
      expect(
        () => RetrievalMetrics(k: 10, recall: 0.8, ndcg: 1.1, mrr: 0.6),
        throwsArgumentError,
      );
      expect(
        () => RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: double.nan),
        throwsArgumentError,
      );
      expect(
        () => RetrievalMetrics.fromMap({
          'k': 10,
          'recall': 0.8,
          'ndcg': 0.7,
          'mrr': 1.5,
        }),
        throwsFormatException,
      );
      expect(
        () => RetrievalMetrics.fromMap({
          'k': 0,
          'recall': 0.8,
          'ndcg': 0.7,
          'mrr': 0.6,
        }),
        throwsFormatException,
      );
      expect(
        () => RetrievalMetrics.fromMap({
          'k': 10,
          'recall': double.nan,
          'ndcg': 0.7,
          'mrr': 0.6,
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed query evaluation artifacts', () {
      final metrics = RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: 0.6);

      expect(
        () => QueryRetrievalEvaluation(
          queryId: ' ',
          metrics: metrics,
          rankedChunkIds: const ['chunk-a'],
          retrievedRelevantChunkIds: const ['chunk-a'],
        ),
        throwsArgumentError,
      );
      expect(
        () => QueryRetrievalEvaluation(
          queryId: 'q1',
          metrics: metrics,
          rankedChunkIds: const [' '],
          retrievedRelevantChunkIds: const ['chunk-a'],
        ),
        throwsArgumentError,
      );
      expect(
        () => QueryRetrievalEvaluation(
          queryId: 'q1',
          metrics: metrics,
          rankedChunkIds: const ['chunk-a'],
          retrievedRelevantChunkIds: const [' '],
        ),
        throwsArgumentError,
      );
      expect(
        () => QueryRetrievalEvaluation(
          queryId: 'q1',
          metrics: metrics,
          rankedChunkIds: const ['chunk-a'],
          retrievedRelevantChunkIds: const ['chunk-z'],
        ),
        throwsArgumentError,
      );
    });

    test(
      'fromMap rejects malformed query evaluation artifacts as format errors',
      () {
        final metrics = RetrievalMetrics(
          k: 10,
          recall: 0.8,
          ndcg: 0.7,
          mrr: 0.6,
        );
        final baseMap = <String, Object?>{
          'queryId': 'q1',
          'metrics': metrics.toMap(),
          'rankedChunkIds': const ['chunk-a'],
          'retrievedRelevantChunkIds': const ['chunk-a'],
        };

        expect(
          () => QueryRetrievalEvaluation.fromMap({...baseMap, 'queryId': ' '}),
          throwsFormatException,
        );
        expect(
          () => QueryRetrievalEvaluation.fromMap({
            ...baseMap,
            'rankedChunkIds': const [' '],
          }),
          throwsFormatException,
        );
        expect(
          () => QueryRetrievalEvaluation.fromMap({
            ...baseMap,
            'retrievedRelevantChunkIds': const [' '],
          }),
          throwsFormatException,
        );
        expect(
          () => QueryRetrievalEvaluation.fromMap({
            ...baseMap,
            'retrievedRelevantChunkIds': const ['chunk-z'],
          }),
          throwsFormatException,
        );
        expect(
          () => QueryRetrievalEvaluation.fromMap({
            ...baseMap,
            'metrics': {...metrics.toMap(), 'mrr': double.nan},
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects aggregate evaluations whose metric cutoffs differ', () {
      final queryEvaluation = QueryRetrievalEvaluation(
        queryId: 'q1',
        metrics: RetrievalMetrics(k: 5, recall: 0.8, ndcg: 0.7, mrr: 0.6),
        rankedChunkIds: const ['chunk-a'],
        retrievedRelevantChunkIds: const ['chunk-a'],
      );
      final average = RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: 0.6);

      expect(
        () => RetrievalEvaluation(queries: [queryEvaluation], average: average),
        throwsArgumentError,
      );
      expect(
        () => RetrievalEvaluation.fromMap({
          'average': average.toMap(),
          'queries': [queryEvaluation.toMap()],
        }),
        throwsFormatException,
      );
    });

    test(
      'rejects aggregate evaluations whose average does not match queries',
      () {
        final queryEvaluation = QueryRetrievalEvaluation(
          queryId: 'q1',
          metrics: RetrievalMetrics(k: 10, recall: 0, ndcg: 0, mrr: 0),
          rankedChunkIds: const ['chunk-z'],
          retrievedRelevantChunkIds: const [],
        );
        final incorrectAverage = RetrievalMetrics(
          k: 10,
          recall: 1,
          ndcg: 1,
          mrr: 1,
        );

        expect(
          () => RetrievalEvaluation(
            queries: [queryEvaluation],
            average: incorrectAverage,
          ),
          throwsArgumentError,
        );
        expect(
          () => RetrievalEvaluation.fromMap({
            'average': incorrectAverage.toMap(),
            'queries': [queryEvaluation.toMap()],
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects aggregate evaluations without query rows', () {
      final average = RetrievalMetrics(k: 10, recall: 0, ndcg: 0, mrr: 0);

      expect(
        () => RetrievalEvaluation(queries: const [], average: average),
        throwsArgumentError,
      );
      expect(
        () => RetrievalEvaluation.fromMap({
          'average': average.toMap(),
          'queries': const [],
        }),
        throwsFormatException,
      );
    });

    test(
      'fromMap rejects malformed aggregate evaluation metrics as format errors',
      () {
        final metrics = RetrievalMetrics(
          k: 10,
          recall: 0.8,
          ndcg: 0.7,
          mrr: 0.6,
        );
        final queryEvaluation = QueryRetrievalEvaluation(
          queryId: 'q1',
          metrics: metrics,
          rankedChunkIds: const ['chunk-a'],
          retrievedRelevantChunkIds: const ['chunk-a'],
        );

        expect(
          () => RetrievalEvaluation.fromMap({
            'average': {...metrics.toMap(), 'mrr': double.nan},
            'queries': [queryEvaluation.toMap()],
          }),
          throwsFormatException,
        );
      },
    );

    test('serializes benchmark reports for CLI regression gates', () {
      final report = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.82,
              ndcg: 0.74,
              mrr: 0.61,
            ),
          ),
        ],
      );

      final decoded = RetrievalBenchmarkReport.fromMap(
        jsonDecode(jsonEncode(report.toMap())) as Map<String, Object?>,
      );

      expect(decoded.k, 10);
      expect(decoded.runNamed('bm25')?.queryCount, 50);
      expect(decoded.runNamed('bm25')?.metrics.ndcg, 0.74);
    });

    test('serializes benchmark reports with optional query-level rows', () {
      final relevantQuery = QueryRetrievalEvaluation(
        queryId: 'q1',
        metrics: RetrievalMetrics(k: 10, recall: 1, ndcg: 1, mrr: 1),
        rankedChunkIds: const ['chunk-a'],
        retrievedRelevantChunkIds: const ['chunk-a'],
      );
      final missedQuery = QueryRetrievalEvaluation(
        queryId: 'q2',
        metrics: RetrievalMetrics(k: 10, recall: 0, ndcg: 0, mrr: 0),
        rankedChunkIds: const ['chunk-b'],
        retrievedRelevantChunkIds: const [],
      );
      final report = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 2,
            metrics: RetrievalMetrics(k: 10, recall: 0.5, ndcg: 0.5, mrr: 0.5),
            queryEvaluations: [relevantQuery, missedQuery],
          ),
        ],
      );

      final decoded = RetrievalBenchmarkReport.fromMap(
        jsonDecode(jsonEncode(report.toMap())) as Map<String, Object?>,
      );
      final decodedRun = decoded.runNamed('bm25')!;

      expect(decodedRun.queryEvaluations, [relevantQuery, missedQuery]);
      expect(
        ((report.toMap()['runs']! as List<Object?>).single!
            as Map<String, Object?>)['queries'],
        isA<List<Object?>>(),
      );
    });

    test('summarizes query metrics by explicit query group', () {
      final dartQuery = QueryRetrievalEvaluation(
        queryId: 'q1',
        metrics: RetrievalMetrics(k: 10, recall: 1, ndcg: 0.8, mrr: 1),
        rankedChunkIds: const ['chunk-a'],
        retrievedRelevantChunkIds: const ['chunk-a'],
      );
      final typescriptQuery = QueryRetrievalEvaluation(
        queryId: 'q2',
        metrics: RetrievalMetrics(k: 10, recall: 0, ndcg: 0, mrr: 0),
        rankedChunkIds: const ['chunk-b'],
        retrievedRelevantChunkIds: const [],
      );
      final markdownQuery = QueryRetrievalEvaluation(
        queryId: 'q3',
        metrics: RetrievalMetrics(k: 10, recall: 1, ndcg: 1, mrr: 1),
        rankedChunkIds: const ['chunk-c'],
        retrievedRelevantChunkIds: const ['chunk-c'],
      );

      final groups = RetrievalEvaluator.summarizeGroups(
        queryEvaluations: [dartQuery, typescriptQuery, markdownQuery],
        groupByQueryId: const {
          'q1': 'dart',
          'q2': 'typescript',
          'q3': 'markdown',
        },
      );
      final report = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 3,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 2 / 3,
              ndcg: 1.8 / 3,
              mrr: 2 / 3,
            ),
            queryEvaluations: [dartQuery, typescriptQuery, markdownQuery],
            queryGroupSummaries: groups,
          ),
        ],
      );

      final decoded = RetrievalBenchmarkReport.fromMap(
        jsonDecode(jsonEncode(report.toMap())) as Map<String, Object?>,
      );
      final decodedGroups = decoded.runNamed('bm25')!.queryGroupSummaries;

      expect(decodedGroups.map((group) => group.name), [
        'dart',
        'typescript',
        'markdown',
      ]);
      expect(
        decodedGroups.singleWhere((group) => group.name == 'dart'),
        {
          RetrievalQueryGroupSummary(
            name: 'dart',
            queryCount: 1,
            metrics: RetrievalMetrics(k: 10, recall: 1, ndcg: 0.8, mrr: 1),
          ),
        }.single,
      );
      expect(
        ((report.toMap()['runs']! as List<Object?>).single!
            as Map<String, Object?>)['queryGroups'],
        isA<List<Object?>>(),
      );
    });

    test('rejects malformed query group summaries', () {
      final query = QueryRetrievalEvaluation(
        queryId: 'q1',
        metrics: RetrievalMetrics(k: 10, recall: 1, ndcg: 1, mrr: 1),
        rankedChunkIds: const ['chunk-a'],
        retrievedRelevantChunkIds: const ['chunk-a'],
      );
      final group = RetrievalQueryGroupSummary(
        name: 'dart',
        queryCount: 1,
        metrics: query.metrics,
      );

      expect(
        () => RetrievalEvaluator.summarizeGroups(
          queryEvaluations: [query],
          groupByQueryId: const {},
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalEvaluator.summarizeGroups(
          queryEvaluations: [query],
          groupByQueryId: const {'q1': 'dart', 'q2': 'dart'},
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalEvaluator.summarizeGroups(
          queryEvaluations: [
            query,
            query.copyWith(metrics: query.metrics.copyWith(k: 5)),
          ],
          groupByQueryId: const {'q1': 'dart'},
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalQueryGroupSummary(
          name: ' ',
          queryCount: 1,
          metrics: query.metrics,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRunSummary(
          name: 'bm25',
          queryCount: 1,
          metrics: query.metrics,
          queryEvaluations: [query],
          queryGroupSummaries: [group, group],
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRunSummary(
          name: 'bm25',
          queryCount: 1,
          metrics: query.metrics,
          queryEvaluations: [query],
          queryGroupSummaries: [
            group.copyWith(metrics: query.metrics.copyWith(recall: 0)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalQueryGroupSummary.fromMap({
          'name': ' ',
          'queryCount': 1,
          'metrics': query.metrics.toMap(),
        }),
        throwsFormatException,
      );
    });

    test('keeps summary-only benchmark reports backward compatible', () {
      final decoded = RetrievalBenchmarkReport.fromMap({
        'k': 10,
        'runs': [
          {
            'name': 'bm25',
            'queryCount': 50,
            'metrics': {'k': 10, 'recall': 0.8, 'ndcg': 0.7, 'mrr': 0.6},
          },
        ],
      });

      expect(decoded.runNamed('bm25')?.queryEvaluations, isEmpty);
    });

    test('rejects malformed benchmark report and run summaries', () {
      final metrics = RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: 0.6);

      expect(
        () => RetrievalRunSummary(name: '', queryCount: 1, metrics: metrics),
        throwsArgumentError,
      );
      expect(
        () =>
            RetrievalRunSummary(name: 'bm25', queryCount: 0, metrics: metrics),
        throwsArgumentError,
      );
      expect(
        () =>
            RetrievalRunSummary(name: 'bm25', queryCount: -1, metrics: metrics),
        throwsArgumentError,
      );
      expect(
        () => RetrievalBenchmarkReport(
          k: 0,
          runs: [
            RetrievalRunSummary(name: 'bm25', queryCount: 1, metrics: metrics),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalBenchmarkReport(k: 10, runs: const []),
        throwsArgumentError,
      );
      expect(
        () => RetrievalBenchmarkReport(
          k: 10,
          runs: [
            RetrievalRunSummary(name: 'bm25', queryCount: 1, metrics: metrics),
            RetrievalRunSummary(name: 'bm25', queryCount: 1, metrics: metrics),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRunSummary(
          name: 'bm25',
          queryCount: 2,
          metrics: metrics,
          queryEvaluations: [
            QueryRetrievalEvaluation(
              queryId: 'q1',
              metrics: metrics,
              rankedChunkIds: const ['chunk-a'],
              retrievedRelevantChunkIds: const ['chunk-a'],
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRunSummary(
          name: 'bm25',
          queryCount: 1,
          metrics: metrics,
          queryEvaluations: [
            QueryRetrievalEvaluation(
              queryId: 'q1',
              metrics: metrics.copyWith(k: 5),
              rankedChunkIds: const ['chunk-a'],
              retrievedRelevantChunkIds: const ['chunk-a'],
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRunSummary(
          name: 'bm25',
          queryCount: 1,
          metrics: metrics,
          queryEvaluations: [
            QueryRetrievalEvaluation(
              queryId: 'q1',
              metrics: metrics.copyWith(recall: 0),
              rankedChunkIds: const ['chunk-a'],
              retrievedRelevantChunkIds: const ['chunk-a'],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects malformed serialized benchmark run summaries', () {
      final metrics = RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: 0.6);
      final baseMap = <String, Object?>{
        'name': 'bm25',
        'queryCount': 1,
        'metrics': metrics.toMap(),
      };

      expect(
        () => RetrievalRunSummary.fromMap({...baseMap, 'name': ' '}),
        throwsFormatException,
      );
      expect(
        () => RetrievalRunSummary.fromMap({...baseMap, 'queryCount': 0}),
        throwsFormatException,
      );
      expect(
        () => RetrievalRunSummary.fromMap({...baseMap, 'queryCount': -1}),
        throwsFormatException,
      );
      expect(
        () => RetrievalRunSummary.fromMap({
          ...baseMap,
          'metrics': {...metrics.toMap(), 'mrr': double.nan},
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed serialized benchmark reports', () {
      final metrics = RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: 0.6);
      final run = RetrievalRunSummary(
        name: 'bm25',
        queryCount: 1,
        metrics: metrics,
      ).toMap();

      expect(
        () => RetrievalBenchmarkReport.fromMap({
          'k': 0,
          'runs': [run],
        }),
        throwsFormatException,
      );
      expect(
        () => RetrievalBenchmarkReport.fromMap({'k': 10, 'runs': const []}),
        throwsFormatException,
      );
      expect(
        () => RetrievalBenchmarkReport.fromMap({
          'k': 10,
          'runs': [run, run],
        }),
        throwsFormatException,
      );
      expect(
        () => RetrievalBenchmarkReport.fromMap({
          'k': 10,
          'runs': [
            {...run, 'metrics': metrics.copyWith(k: 5).toMap()},
          ],
        }),
        throwsFormatException,
      );
    });

    test('uses value equality for serializable DTOs', () {
      final judgments = RelevanceJudgments.fromMap({
        'encrypt data': {'chunk-a': 3, 'chunk-b': 2},
      });
      expect(RelevanceJudgments.fromMap(judgments.toMap()), judgments);

      final metrics = RetrievalMetrics(k: 10, recall: 0.8, ndcg: 0.7, mrr: 0.6);
      final queryEvaluation = QueryRetrievalEvaluation(
        queryId: 'encrypt-data',
        metrics: metrics,
        rankedChunkIds: const ['chunk-a', 'chunk-z'],
        retrievedRelevantChunkIds: const ['chunk-a'],
      );
      final evaluation = RetrievalEvaluation(
        queries: [queryEvaluation],
        average: metrics,
      );
      expect(RetrievalEvaluation.fromMap(evaluation.toMap()), evaluation);

      final report = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(name: 'bm25', queryCount: 1, metrics: metrics),
        ],
      );
      expect(RetrievalBenchmarkReport.fromMap(report.toMap()), report);

      final issue = RetrievalRegressionIssue(
        runName: 'bm25',
        metricName: 'recall',
        baselineValue: 0.9,
        currentValue: 0.8,
        allowedDrop: 0.05,
        actualDrop: 0.1,
      );
      expect(
        RetrievalRegressionGateResult(issues: [issue]),
        RetrievalRegressionGateResult(issues: [issue]),
      );
      // The gate result is a report artifact; nothing reads it back.
      expect(RetrievalRegressionGateResult(issues: [issue]).toMap(), {
        'passed': false,
        'issues': [issue.toMap()],
      });
    });

    test('toMap returns detached mutable collection snapshots', () {
      final judgments = RelevanceJudgments.fromMap({
        'encrypt data': {'chunk-a': 3, 'chunk-b': 2},
      });
      final judgmentsMap = judgments.toMap();
      final serializedJudgments =
          judgmentsMap['encrypt data']! as Map<String, int>;

      serializedJudgments['chunk-a'] = 0;

      expect(serializedJudgments['chunk-a'], 0);
      expect(judgments.relevanceByQuery['encrypt data']!['chunk-a'], 3);

      final metrics = RetrievalMetrics(k: 10, recall: 1, ndcg: 1, mrr: 1);
      final queryEvaluation = QueryRetrievalEvaluation(
        queryId: 'encrypt-data',
        metrics: metrics,
        rankedChunkIds: const ['chunk-a', 'chunk-b'],
        retrievedRelevantChunkIds: const ['chunk-a'],
      );
      final queryMap = queryEvaluation.toMap();
      final serializedRanked = queryMap['rankedChunkIds']! as List<String>;
      final serializedRelevant =
          queryMap['retrievedRelevantChunkIds']! as List<String>;

      serializedRanked[0] = 'chunk-z';
      serializedRelevant.clear();

      expect(serializedRanked, ['chunk-z', 'chunk-b']);
      expect(serializedRelevant, isEmpty);
      expect(queryEvaluation.rankedChunkIds, ['chunk-a', 'chunk-b']);
      expect(queryEvaluation.retrievedRelevantChunkIds, ['chunk-a']);
    });

    test('flags recall and nDCG drops beyond configured thresholds', () {
      final baseline = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.90,
              ndcg: 0.80,
              mrr: 0.70,
            ),
          ),
        ],
      );
      final current = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.84,
              ndcg: 0.76,
              mrr: 0.69,
            ),
          ),
        ],
      );

      final result = RetrievalRegressionGate.evaluate(
        current: current,
        baseline: baseline,
        maxRecallDrop: 0.05,
        maxNdcgDrop: 0.03,
      );

      expect(result.passed, isFalse);
      expect(
        result.issues.map((issue) => '${issue.runName}:${issue.metricName}'),
        containsAll(['bm25:recall', 'bm25:ndcg']),
      );
    });

    test('flags query group drops hidden by aggregate metrics', () {
      final baseline = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.80,
              ndcg: 0.80,
              mrr: 0.80,
            ),
            queryGroupSummaries: [
              RetrievalQueryGroupSummary(
                name: 'dart',
                queryCount: 25,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 0.80,
                  ndcg: 0.80,
                  mrr: 0.80,
                ),
              ),
              RetrievalQueryGroupSummary(
                name: 'typescript',
                queryCount: 25,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 0.80,
                  ndcg: 0.80,
                  mrr: 0.80,
                ),
              ),
            ],
          ),
        ],
      );
      final current = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.80,
              ndcg: 0.80,
              mrr: 0.80,
            ),
            queryGroupSummaries: [
              RetrievalQueryGroupSummary(
                name: 'dart',
                queryCount: 25,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 0.90,
                  ndcg: 0.90,
                  mrr: 0.90,
                ),
              ),
              RetrievalQueryGroupSummary(
                name: 'typescript',
                queryCount: 25,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 0.70,
                  ndcg: 0.70,
                  mrr: 0.70,
                ),
              ),
            ],
          ),
        ],
      );

      final result = RetrievalRegressionGate.evaluate(
        current: current,
        baseline: baseline,
        maxRecallDrop: 0.05,
        maxNdcgDrop: 0.03,
      );

      expect(result.passed, isFalse);
      expect(result.issues, hasLength(2));
      expect(
        result.issues.map(
          (issue) =>
              '${issue.runName}:${issue.queryGroupName}:${issue.metricName}',
        ),
        containsAll(['bm25:typescript:recall', 'bm25:typescript:ndcg']),
      );
    });

    test('flags missing and extra query group summaries', () {
      final baseline = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 2,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.75,
              ndcg: 0.75,
              mrr: 0.75,
            ),
            queryGroupSummaries: [
              RetrievalQueryGroupSummary(
                name: 'dart',
                queryCount: 1,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 1.0,
                  ndcg: 1.0,
                  mrr: 1.0,
                ),
              ),
              RetrievalQueryGroupSummary(
                name: 'typescript',
                queryCount: 1,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 0.5,
                  ndcg: 0.5,
                  mrr: 0.5,
                ),
              ),
            ],
          ),
        ],
      );
      final current = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 2,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.75,
              ndcg: 0.75,
              mrr: 0.75,
            ),
            queryGroupSummaries: [
              RetrievalQueryGroupSummary(
                name: 'dart',
                queryCount: 1,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 1.0,
                  ndcg: 1.0,
                  mrr: 1.0,
                ),
              ),
              RetrievalQueryGroupSummary(
                name: 'markdown',
                queryCount: 1,
                metrics: RetrievalMetrics(
                  k: 10,
                  recall: 0.5,
                  ndcg: 0.5,
                  mrr: 0.5,
                ),
              ),
            ],
          ),
        ],
      );

      final result = RetrievalRegressionGate.evaluate(
        current: current,
        baseline: baseline,
      );

      expect(result.passed, isFalse);
      expect(
        result.issues.map(
          (issue) =>
              '${issue.runName}:${issue.queryGroupName}:${issue.metricName}',
        ),
        containsAll(['bm25:typescript:queryGroup', 'bm25:markdown:queryGroup']),
      );
    });

    test('rejects invalid regression gate thresholds', () {
      final report = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.90,
              ndcg: 0.80,
              mrr: 0.70,
            ),
          ),
        ],
      );

      expect(
        () => RetrievalRegressionGate.evaluate(
          current: report,
          baseline: report,
          maxRecallDrop: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionGate.evaluate(
          current: report,
          baseline: report,
          maxNdcgDrop: double.infinity,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionGate.evaluate(
          current: report,
          baseline: report,
          maxMrrDrop: double.negativeInfinity,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionGate.evaluate(
          current: report,
          baseline: report,
          maxRecallDrop: 1.01,
        ),
        throwsArgumentError,
      );
    });

    test('rejects malformed regression issues', () {
      expect(
        () => RetrievalRegressionIssue(
          runName: ' ',
          metricName: 'recall',
          baselineValue: 0.9,
          currentValue: 0.8,
          allowedDrop: 0.05,
          actualDrop: 0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionIssue(
          runName: 'bm25',
          metricName: '\t',
          baselineValue: 0.9,
          currentValue: 0.8,
          allowedDrop: 0.05,
          actualDrop: 0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionIssue(
          runName: 'bm25',
          metricName: 'recall',
          baselineValue: double.nan,
          currentValue: 0.8,
          allowedDrop: 0.05,
          actualDrop: 0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionIssue(
          runName: 'bm25',
          metricName: 'recall',
          baselineValue: 0.9,
          currentValue: 0.8,
          allowedDrop: null,
          actualDrop: 0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetrievalRegressionIssue(
          runName: 'bm25',
          metricName: 'recall',
          baselineValue: 0.9,
          currentValue: 0.8,
          allowedDrop: 0.2,
          actualDrop: 0.1,
        ),
        throwsArgumentError,
      );
    });

    test('serializes regression issues for reports', () {
      final issue = RetrievalRegressionIssue(
        runName: 'bm25',
        queryGroupName: 'typescript',
        metricName: 'recall',
        baselineValue: 0.9,
        currentValue: 0.8,
        allowedDrop: 0.05,
        actualDrop: 0.1,
      );

      expect(issue.toMap(), {
        'runName': 'bm25',
        'queryGroupName': 'typescript',
        'metricName': 'recall',
        'baselineValue': 0.9,
        'currentValue': 0.8,
        'allowedDrop': 0.05,
        'actualDrop': 0.1,
      });
    });

    test('flags benchmark reports with different cutoffs', () {
      final baseline = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.90,
              ndcg: 0.80,
              mrr: 0.70,
            ),
          ),
        ],
      );
      final current = RetrievalBenchmarkReport(
        k: 5,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 5,
              recall: 0.90,
              ndcg: 0.80,
              mrr: 0.70,
            ),
          ),
        ],
      );

      final result = RetrievalRegressionGate.evaluate(
        current: current,
        baseline: baseline,
      );

      expect(result.passed, isFalse);
      expect(result.issues, [
        RetrievalRegressionIssue(
          runName: 'benchmark',
          metricName: 'k',
          baselineValue: 10,
          currentValue: 5,
          allowedDrop: null,
          actualDrop: null,
        ),
      ]);
    });

    test('flags benchmark runs with different query counts', () {
      final baseline = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 50,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.90,
              ndcg: 0.80,
              mrr: 0.70,
            ),
          ),
        ],
      );
      final current = RetrievalBenchmarkReport(
        k: 10,
        runs: [
          RetrievalRunSummary(
            name: 'bm25',
            queryCount: 49,
            metrics: RetrievalMetrics(
              k: 10,
              recall: 0.90,
              ndcg: 0.80,
              mrr: 0.70,
            ),
          ),
        ],
      );

      final result = RetrievalRegressionGate.evaluate(
        current: current,
        baseline: baseline,
      );

      expect(result.passed, isFalse);
      expect(result.issues, [
        RetrievalRegressionIssue(
          runName: 'bm25',
          metricName: 'queryCount',
          baselineValue: 50,
          currentValue: 49,
          allowedDrop: null,
          actualDrop: null,
        ),
      ]);
    });

    test('rejects benchmark reports whose run metric cutoff differs', () {
      expect(
        () => RetrievalBenchmarkReport(
          k: 10,
          runs: [
            RetrievalRunSummary(
              name: 'bm25',
              queryCount: 50,
              metrics: RetrievalMetrics(
                k: 5,
                recall: 0.90,
                ndcg: 0.80,
                mrr: 0.70,
              ),
            ),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('metrics use k=5'),
          ),
        ),
      );
    });
  });
}

double _log2(num value) => math.log(value) / math.ln2;
