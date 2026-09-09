// ignore_for_file: avoid_slow_async_io
// Tests create small temporary query files for CLI parser coverage.
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/compare_options.dart';
import '../tool/src/retrieval_evaluator.dart';

/// Returns the run labels the descriptors resolve to.
List<String> runLabels(Iterable<String> descriptors) =>
    resolveComparisonRuns(descriptors).map((run) => run.label).toList();

/// Returns the query texts the arguments resolve to.
List<String> queryTexts(
  List<String> args, {
  Iterable<String>? fallbackQueryIds,
  bool requireExplicitQueries = false,
}) {
  return uniqueQueryTexts(
    loadQueries(
      CompareOptions.parse(args).queriesPath,
      fallback: fallbackQueryIds,
      requireExplicitQueries: requireExplicitQueries,
    ),
  );
}

Matcher throwsArgumentErrorSaying(String fragment) => throwsA(
  isA<ArgumentError>().having(
    (error) => error.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  group('compare_embeddings CLI', () {
    test('requires explicit query text mappings for qrels ids', () {
      expect(
        () => queryTexts(
          const [],
          fallbackQueryIds: ['q001'],
          requireExplicitQueries: true,
        ),
        throwsArgumentErrorSaying('requires --queries'),
      );
    });

    test('rejects qrels ids missing from the query text mapping', () {
      expect(
        () => validateQrelsQueryIdCoverage(['q001', 'q002'], ['q001']),
        throwsArgumentErrorSaying('without a --queries mapping'),
      );
      expect(
        () => validateQrelsQueryIdCoverage(['q001'], ['q001', 'q999']),
        throwsArgumentErrorSaying('not present in qrels'),
      );
    });

    test('loads query group mappings from JSON files', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'compare_embeddings_query_groups_test',
      );
      try {
        final groups = File('${tempDir.path}/groups.json')
          ..writeAsStringSync('{"q001":"dart","q002":{"group":"typescript"}}');

        expect(loadQueryGroups(explicitPath: groups.path), {
          'q001': 'dart',
          'q002': 'typescript',
        });
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects query group mappings that do not match qrels ids', () {
      expect(
        () => validateQueryGroupMappings(
          const ['q001', 'q002'],
          const {'q001': 'dart'},
        ),
        throwsArgumentErrorSaying('without a query group'),
      );
      expect(
        () => validateQueryGroupMappings(
          const ['q001'],
          const {'q001': 'dart', 'q999': 'dart'},
        ),
        throwsArgumentErrorSaying('not present in qrels'),
      );
    });

    test(
      'keeps built-in default queries when qrels are not being evaluated',
      () {
        expect(queryTexts(const []), [
          'encrypt sensitive data',
          'refresh auth token',
          'calculate order total',
        ]);
      },
    );

    test('rejects blank and bare query file option values', () {
      expect(
        () => queryTexts(const ['--queries=']),
        throwsArgumentErrorSaying('--queries requires a file path'),
      );
      expect(
        () => queryTexts(const ['--queries']),
        throwsArgumentErrorSaying('queries'),
      );
    });

    test('rejects blank qrels file option values', () {
      expect(
        () => CompareOptions.parse(const ['--qrels=']),
        throwsArgumentErrorSaying('--qrels requires a file path'),
      );
    });

    test('rejects blank comparison fixture and output path values', () {
      final defaults = CompareOptions.parse(const []);
      expect(defaults.fixturesRoot, 'fixtures/corpus');
      expect(defaults.outputDir, 'comparison_results');

      expect(
        () => CompareOptions.parse(const ['--fixtures=']),
        throwsArgumentErrorSaying('--fixtures requires a file path'),
      );
      expect(
        () => CompareOptions.parse(const ['--output=']),
        throwsArgumentErrorSaying('--output requires a file path'),
      );
    });

    test('rejects unknown requested embedder descriptors', () {
      expect(
        () => runLabels(['bm25', 'not-a-model']),
        throwsArgumentErrorSaying("Unknown semantic embedder 'not-a-model'"),
      );
    });

    test('rejects malformed embedder descriptors', () {
      expect(
        () => runLabels(['hybrid:']),
        throwsArgumentErrorSaying(
          'hybrid descriptor requires a dense embedder name',
        ),
      );
      expect(
        () => runLabels(['ollama:']),
        throwsArgumentErrorSaying('ollama descriptor requires a model name'),
      );
      expect(
        () => runLabels(['rerank:']),
        throwsArgumentErrorSaying(
          'rerank descriptor requires a base run descriptor',
        ),
      );
    });

    test('rejects duplicate comparison run labels', () {
      expect(
        () => runLabels(['bm25', 'lexical']),
        throwsArgumentErrorSaying("Duplicate comparison run label 'bm25'"),
      );
    });

    test('rejects duplicate embedder descriptors from CLI args', () {
      expect(
        () => runLabels(
          CompareOptions.parse(const [
            '--embedders=bm25,bm25',
          ]).embedderDescriptors,
        ),
        throwsArgumentErrorSaying("Duplicate comparison run label 'bm25'"),
      );
    });

    test('rejects empty embedder descriptor option values', () {
      expect(
        () => CompareOptions.parse(const ['--embedders=']),
        throwsArgumentErrorSaying('--embedders requires a value'),
      );
      expect(
        () => CompareOptions.parse(const ['--embedders=,']),
        throwsArgumentErrorSaying('--embedders requires at least one'),
      );
      expect(
        () => CompareOptions.parse(const ['--embedders=bm25,,hybrid']),
        throwsArgumentErrorSaying('--embedders contains an empty descriptor'),
      );
    });

    test('resolves valid comparison run labels', () {
      expect(
        runLabels([
          'bm25',
          'hybrid:qwen3',
          'hybrid:embeddinggemma',
          'hybrid:embeddinggemma@512',
          'ollama:embeddinggemma',
          'ollama:nomic-embed-text',
          'rerank:bm25',
          'rerank:hybrid:qwen3',
        ]),
        [
          'bm25',
          'hybrid-qwen3',
          'hybrid-embeddinggemma',
          'hybrid-embeddinggemma-512',
          'ollama-embeddinggemma',
          'ollama-nomic-embed-text',
          'rerank-bm25',
          'rerank-hybrid-qwen3',
        ],
      );
    });

    test('requires a reranker endpoint for reranked runs', () {
      expect(
        () => validateRerankerOptions(
          resolveComparisonRuns(const ['rerank:bm25']),
          null,
        ),
        throwsArgumentErrorSaying(
          'Reranked comparison runs require --reranker-url',
        ),
      );
      expect(
        () => validateRerankerOptions(
          resolveComparisonRuns(const ['bm25']),
          null,
        ),
        returnsNormally,
      );
    });

    test('rejects duplicate query ids in query files', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'compare_embeddings_queries_test',
      );
      try {
        final queries = File('${tempDir.path}/queries.tsv')
          ..writeAsStringSync(
            'q001\trefresh auth token\n'
            'q001\tencrypt data\n',
          );

        expect(
          () => queryTexts(['--queries=${queries.path}']),
          throwsArgumentErrorSaying("Duplicate query id 'q001'"),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('defaults to memory storage', () {
      expect(CompareOptions.parse(const []).storeKind, 'memory');
      expect(
        CompareOptions.parse(const ['--store=memory']).storeKind,
        'memory',
      );
      expect(
        CompareOptions.parse(const ['--store=objectbox']).storeKind,
        'objectbox',
      );
    });

    test('rejects unsupported store options', () {
      expect(
        () => CompareOptions.parse(const ['--store=temporary']),
        throwsArgumentErrorSaying('"temporary" is not an allowed value'),
      );
    });

    test('resolves reranker endpoint URLs', () {
      expect(CompareOptions.parse(const []).rerankerUrl, isNull);
      expect(
        CompareOptions.parse(const [
          '--reranker-url=http://127.0.0.1:8080',
        ]).rerankerUrl.toString(),
        'http://127.0.0.1:8080',
      );
      expect(
        () => CompareOptions.parse(const ['--reranker-url=']),
        throwsArgumentErrorSaying('--reranker-url requires a value'),
      );
      expect(
        () => CompareOptions.parse(const ['--reranker-url=file:///tmp/r']),
        throwsArgumentErrorSaying(
          '--reranker-url must be an absolute HTTP(S) URL',
        ),
      );
    });

    test('resolves reranker request timeout', () {
      expect(
        CompareOptions.parse(const []).rerankerRequestTimeout.inSeconds,
        30,
      );
      expect(
        CompareOptions.parse(const [
          '--reranker-timeout-seconds=120',
        ]).rerankerRequestTimeout.inSeconds,
        120,
      );
      expect(
        () => CompareOptions.parse(const ['--reranker-timeout-seconds=']),
        throwsArgumentErrorSaying(
          '--reranker-timeout-seconds requires a value',
        ),
      );
      expect(
        () => CompareOptions.parse(const ['--reranker-timeout-seconds=0']),
        throwsArgumentErrorSaying(
          '--reranker-timeout-seconds must be a positive integer',
        ),
      );
    });

    test('resolves qrels match modes', () {
      expect(
        CompareOptions.parse(const []).qrelsMatchMode,
        QrelsMatchMode.stableId,
      );
      expect(
        CompareOptions.parse(const [
          '--qrels-match=span-overlap',
        ]).qrelsMatchMode,
        QrelsMatchMode.spanOverlap,
      );
      expect(
        () => CompareOptions.parse(const ['--qrels-match=distance']),
        throwsArgumentErrorSaying('"distance" is not an allowed value'),
      );
    });

    test('resolves chunk budget overrides', () {
      final shared = CompareOptions.parse(const [
        '--chunk-budget=800',
      ]).chunking;
      expect(shared.dartMaxChunkLength, 800);
      expect(shared.typescriptMaxChunkLength, 800);
      expect(shared.markdownMaxChunkLength, 800);
      expect(shared.textMaxChunkLength, 800);

      final specific = CompareOptions.parse(const [
        '--chunk-budget=800',
        '--typescript-chunk-budget=500',
      ]).chunking;
      expect(specific.typescriptMaxChunkLength, 500);

      final alias = CompareOptions.parse(const [
        '--ts-chunk-budget=400',
      ]).chunking;
      expect(alias.typescriptMaxChunkLength, 400);
    });

    test('rejects blank numeric option values', () {
      expect(
        () => CompareOptions.parse(const ['--chunk-budget=']),
        throwsArgumentErrorSaying('--chunk-budget requires a value'),
      );
      expect(
        () => CompareOptions.parse(const ['--max-recall-drop=']),
        throwsArgumentErrorSaying('--max-recall-drop requires a value'),
      );
    });

    test('formats query group regression issue labels', () {
      final runIssue = RetrievalRegressionIssue(
        runName: 'bm25',
        metricName: 'recall',
        baselineValue: 0.9,
        currentValue: 0.8,
        allowedDrop: 0.05,
        actualDrop: 0.1,
      );
      final groupIssue = RetrievalRegressionIssue(
        runName: 'bm25',
        queryGroupName: 'typescript',
        metricName: 'ndcg',
        baselineValue: 0.9,
        currentValue: 0.8,
        allowedDrop: 0.03,
        actualDrop: 0.1,
      );

      expect(formatRegressionIssueName(runIssue), 'bm25.recall');
      expect(formatRegressionIssueName(groupIssue), 'bm25[typescript].ndcg');
    });

    test('resolves regression gate threshold overrides', () {
      final defaults = CompareOptions.parse(const []).regressionGate;
      expect(defaults.maxRecallDrop, 0.05);
      expect(defaults.maxNdcgDrop, 0.03);
      expect(defaults.maxMrrDrop, isNull);

      final overrides = CompareOptions.parse(const [
        '--max-recall-drop=0.02',
        '--max-ndcg-drop=0.01',
        '--max-mrr-drop=0.04',
      ]).regressionGate;
      expect(overrides.maxRecallDrop, 0.02);
      expect(overrides.maxNdcgDrop, 0.01);
      expect(overrides.maxMrrDrop, 0.04);
    });
  });
}
