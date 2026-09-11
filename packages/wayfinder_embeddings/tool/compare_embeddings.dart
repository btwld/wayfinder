#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'src/compare_options.dart';
import 'src/pipeline_workflow.dart' as workflow;
import 'src/retrieval_evaluator.dart';

// ignore_for_file: avoid_slow_async_io
// CLI comparison outputs are written synchronously to keep tooling simple.

Future<void> main(List<String> args) async {
  if (shouldSkipComparison(args)) {
    stdout.writeln('Embedding comparison skipped by configuration.');
    return;
  }

  stdout.writeln('Starting embedding comparison...');

  late final CompareOptions options;
  late final RelevanceJudgments? judgments;
  late final Map<String, String>? queryGroupsById;
  late final List<QuerySpec> querySpecs;
  late final List<ComparisonRun> comparisonRuns;
  try {
    options = CompareOptions.parse(args);
    judgments = loadJudgments(options.qrelsPath);
    queryGroupsById = loadQueryGroups(
      explicitPath: options.queryGroupsPath,
      qrelsPath: options.qrelsPath,
    );
    querySpecs = loadQueries(
      options.queriesPath,
      fallback: judgments?.queryIds,
      requireExplicitQueries: judgments != null,
    );
    if (judgments != null) {
      validateQrelsQueryMappings(judgments.queryIds, querySpecs);
      if (queryGroupsById != null) {
        validateQueryGroupMappings(judgments.queryIds, queryGroupsById);
      }
    }
    comparisonRuns = resolveComparisonRuns(
      options.embedderDescriptors,
      modelFile: options.modelPath == null ? null : File(options.modelPath!),
      longInputPolicy: options.longInputPolicy,
    );
    validateRerankerOptions(comparisonRuns, options.rerankerUrl);
  } on ArgumentError catch (error) {
    _exitWithArgumentError(error);
  }

  final queries = uniqueQueryTexts(querySpecs);
  final topK = options.topK;
  final candidateLimit = options.candidateLimit;
  final chunking = options.chunking;
  final metricsOutputPath = options.metricsOutputPath;
  final baselineMetricsPath = options.baselineMetricsPath;
  final storeKind = options.storeKind;
  final rerankerUrl = options.rerankerUrl;
  final rerankerRequestTimeout = options.rerankerRequestTimeout;
  final qrelsMatchMode = options.qrelsMatchMode;
  final validateGolden = options.validateGolden;

  if (queries.isEmpty) {
    stderr.writeln(
      'No queries provided. Provide a query list via --queries=FILE.',
    );
    exit(1);
  }
  if ((metricsOutputPath != null || baselineMetricsPath != null) &&
      judgments == null) {
    stderr.writeln(
      'Retrieval metrics require --qrels. Provide --qrels=FILE when using '
      '--metrics-output or --baseline-metrics.',
    );
    exit(1);
  }
  if (queryGroupsById != null && judgments == null) {
    stderr.writeln(
      'Query group summaries require --qrels. Provide --qrels=FILE when '
      'using --query-groups.',
    );
    exit(1);
  }

  workflow.FixtureConfig config;
  try {
    config = workflow.resolveFixtureConfig(
      fixturesRoot: options.fixturesRoot,
      outputDir: options.outputDir,
    );
  } on FileSystemException catch (error) {
    stderr.writeln('Error: ${error.message} at ${error.path}');
    exit(1);
  }

  stdout.writeln('Processing fixtures at: ${config.fixturesRoot.path}');
  stdout.writeln(
    'Comparison outputs will be written to: ${config.outputDir.path}',
  );
  if (judgments != null) {
    stdout.writeln(
      'Retrieval evaluation: ${judgments.relevanceByQuery.length} qrels queries loaded.',
    );
    stdout.writeln('Qrels matching: ${qrelsMatchMode.label}.');
    if (queryGroupsById != null) {
      stdout.writeln(
        'Query groups: ${queryGroupsById.values.toSet().length} group(s) loaded.',
      );
    }
  }
  if (chunking.hasOverrides) {
    stdout.writeln(
      'Chunk budgets: dart=${chunking.dartMaxChunkLength ?? 'default'}, '
      'typescript=${chunking.typescriptMaxChunkLength ?? 'default'}, '
      'markdown=${chunking.markdownMaxChunkLength ?? 'default'}, '
      'text=${chunking.textMaxChunkLength ?? 'default'} '
      '(non-whitespace characters).',
    );
  }
  if (comparisonRuns.any((run) => run.rerank)) {
    stdout.writeln('Reranker endpoint: $rerankerUrl');
    stdout.writeln('Reranker timeout: ${rerankerRequestTimeout.inSeconds}s.');
  }
  switch (storeKind) {
    case 'objectbox':
      stdout.writeln('Storage backend: ObjectBox (persistent)');
      break;
    case 'memory':
      stdout.writeln('Storage backend: MemoryStore (in-memory)');
      break;
    default:
      throw StateError('Unsupported store kind: $storeKind');
  }

  final files = workflow.collectFixtureFiles(config.fixturesRoot);
  if (files.isEmpty) {
    stderr.writeln('No fixtures detected. Nothing to compare.');
    exit(1);
  }

  stdout.writeln('\n1. Building chunk registry and previewing corpus...');
  final registry = workflow.buildDefaultRegistry(chunking: chunking);
  final preview = await workflow.runPreview(
    registry: registry,
    files: files,
    fixturesDir: config.fixturesRoot,
    onFileProcessed: (file, chunks) {
      final relative = p.relative(file.path, from: config.fixturesRoot.path);
      stdout.writeln('  • $relative -> ${chunks.length} chunks');
    },
  );
  stdout.writeln('Preview produced ${preview.chunks.length} total chunks.');

  workflow.FixtureSpanRelevance? spanRelevance;
  if (judgments != null && qrelsMatchMode == QrelsMatchMode.spanOverlap) {
    stdout.writeln('Resolving stable qrels ids to reference source spans...');
    try {
      final referenceChunks = chunking.hasOverrides
          ? (await workflow.runPreview(
              registry: workflow.buildDefaultRegistry(),
              files: files,
              fixturesDir: config.fixturesRoot,
            )).chunks
          : preview.chunks;
      spanRelevance = workflow.FixtureSpanRelevance.fromJudgments(
        judgments: judgments,
        referenceChunks: referenceChunks,
        fixturesDir: config.fixturesRoot,
      );
    } on FormatException catch (error) {
      stderr.writeln('Invalid span-overlap qrels: $error');
      exit(1);
    }
  }

  if (validateGolden) {
    stdout.writeln('\n2. Validating chunk manifest against golden snapshot...');
    try {
      await workflow.validateAgainstGolden(
        packageRoot: config.packageRoot,
        fixturesDir: config.fixturesRoot,
        preview: preview,
      );
    } on StateError catch (error) {
      stderr.writeln(error);
      stderr.writeln(
        'Inspect ${config.outputDir.path} or rerun with UPDATE_GOLDENS=1.',
      );
      exit(1);
    }
  } else {
    stdout.writeln(
      '\n2. Skipping golden comparison (enable with --validate-golden).',
    );
  }

  stdout.writeln('\n3. Running per-embedder ingestion and search...');
  final comparisonResults = <String, workflow.IngestionResult>{};
  final failedRuns = <String>[];

  for (final run in comparisonRuns) {
    try {
      final output = Directory(p.join(config.outputDir.path, run.label))
        ..createSync(recursive: true);
      stdout.writeln('\n→ ${run.label}');

      final ingestion = switch (run.kind) {
        ComparisonRunKind.lexical => await workflow.persistLexicalSearch(
          registry: registry,
          files: files,
          fixturesDir: config.fixturesRoot,
          outputDir: output,
          dryRunChunks: preview.chunks,
          queries: queries,
          topK: topK,
          candidateLimit: candidateLimit,
          storeFactory: storeFactory(run.label, storeKind),
          rerankerFactory: rerankerFactory(
            run,
            rerankerUrl,
            rerankerRequestTimeout,
          ),
        ),
        ComparisonRunKind.semantic ||
        ComparisonRunKind.hybrid => await workflow.persistAndSearch(
          registry: registry,
          files: files,
          fixturesDir: config.fixturesRoot,
          outputDir: output,
          dryRunChunks: preview.chunks,
          queries: queries,
          topK: topK,
          candidateLimit: candidateLimit,
          embedderFactory: run.embedderFactory!,
          searcherFactory: run.kind == ComparisonRunKind.hybrid
              ? workflow.hybridSearcherFactory
              : workflow.denseSearcherFactory,
          rerankerFactory: rerankerFactory(
            run,
            rerankerUrl,
            rerankerRequestTimeout,
          ),
          storeFactory: storeFactory(run.label, storeKind),
        ),
      };

      comparisonResults[run.label] = ingestion;
      if (ingestion.skippedFiles.isNotEmpty) {
        stdout.writeln('  Skipped files: ${ingestion.skippedFiles.join(', ')}');
      }
      stdout.writeln('  Saved chunks to: ${ingestion.chunksPath}');
      stdout.writeln('  Saved embeddings to: ${ingestion.embeddingsPath}');
      stdout.writeln('  Saved queries to: ${ingestion.queriesPath}');
      stdout.writeln(
        '  Saved search results to: ${ingestion.searchResultsPath}',
      );
      stdout.writeln(
        '  Top result: ${_topResultSummary(ingestion, config.fixturesRoot)}',
      );
    } catch (error, stack) {
      failedRuns.add(run.label);
      stderr.writeln('  Failed to run ${run.label}: $error');
      stderr.writeln(stack);
    }
  }

  if (failedRuns.isNotEmpty) {
    stderr.writeln(
      'Comparison failed for requested run(s): ${failedRuns.join(', ')}.',
    );
    exit(1);
  }

  if (comparisonResults.isEmpty) {
    stderr.writeln('No comparison runs completed successfully.');
    exit(1);
  }

  stdout.writeln(
    '\n4. Computing cross-embedder overlap (top $topK results)...',
  );
  final benchmarkReport = judgments == null
      ? null
      : _buildBenchmarkReport(
          results: comparisonResults,
          judgments: judgments,
          spanRelevance: spanRelevance,
          querySpecs: querySpecs,
          queryGroupsById: queryGroupsById,
          fixturesDir: config.fixturesRoot,
          topK: topK,
        );
  final summary = _buildComparisonSummary(
    comparisonResults,
    querySpecs,
    topK,
    benchmarkReport: benchmarkReport,
  );
  final summaryPath = p.join(config.outputDir.path, 'comparison_summary.md');
  File(summaryPath).writeAsStringSync(summary);
  stdout.writeln(summary);
  stdout.writeln('\nDetailed summary saved to: $summaryPath');

  if (metricsOutputPath != null && benchmarkReport != null) {
    _writeBenchmarkReport(metricsOutputPath, benchmarkReport);
    stdout.writeln('Metrics report saved to: $metricsOutputPath');
  }

  if (baselineMetricsPath != null && benchmarkReport != null) {
    final baseline = _loadBenchmarkReport(baselineMetricsPath);
    final gateResult = RetrievalRegressionGate.evaluate(
      current: benchmarkReport,
      baseline: baseline,
      maxRecallDrop: options.regressionGate.maxRecallDrop,
      maxNdcgDrop: options.regressionGate.maxNdcgDrop,
      maxMrrDrop: options.regressionGate.maxMrrDrop,
    );
    if (!gateResult.passed) {
      stderr.writeln('Retrieval regression gate failed:');
      for (final issue in gateResult.issues) {
        if (issue.metricName == 'run') {
          stderr.writeln('  - Missing run: ${issue.runName}');
          continue;
        }
        if (issue.allowedDrop == null || issue.actualDrop == null) {
          stderr.writeln(
            '  - Incompatible ${formatRegressionIssueName(issue)}: '
            'baseline=${_formatRegressionValue(issue.baselineValue)}, '
            'current=${_formatRegressionValue(issue.currentValue)}',
          );
          continue;
        }
        stderr.writeln(
          '  - ${formatRegressionIssueName(issue)}: '
          'baseline=${issue.baselineValue?.toStringAsFixed(3)}, '
          'current=${issue.currentValue?.toStringAsFixed(3)}, '
          'drop=${issue.actualDrop?.toStringAsFixed(3)} '
          '(allowed ${issue.allowedDrop?.toStringAsFixed(3)})',
        );
      }
      exit(1);
    }
    stdout.writeln('Retrieval regression gate passed.');
  }

  stdout.writeln('\nEmbedding comparison completed successfully!');
}

Never _exitWithArgumentError(ArgumentError error) {
  stderr.writeln(error.message ?? error);
  exit(1);
}

String _formatRegressionValue(double? value) {
  if (value == null) {
    return 'n/a';
  }
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(3);
}

RetrievalBenchmarkReport _loadBenchmarkReport(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Baseline metrics file not found: ${file.path}');
    exit(1);
  }

  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      stderr.writeln('Baseline metrics file must contain a JSON object.');
      exit(1);
    }
    return RetrievalBenchmarkReport.fromMap(decoded);
  } on FormatException catch (error) {
    stderr.writeln('Invalid baseline metrics file: $error');
    exit(1);
  } on Object catch (error) {
    stderr.writeln('Failed to read baseline metrics file: $error');
    exit(1);
  }
}

void _writeBenchmarkReport(String path, RetrievalBenchmarkReport report) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(report.toMap())}\n');
}

String _topResultSummary(
  workflow.IngestionResult ingestion,
  Directory fixturesDir,
) {
  if (ingestion.searchResultsByQuery.isEmpty) {
    return 'no search results';
  }
  final firstQuery = ingestion.searchResultsByQuery.keys.first;
  final results = ingestion.searchResultsByQuery[firstQuery] ?? const [];
  if (results.isEmpty) {
    return 'no search results for "$firstQuery"';
  }
  final top = results.first;
  final relative = p.relative(top.chunk.sourcePath, from: fixturesDir.path);
  return '"$firstQuery" → $relative:${top.chunk.lineStart}-${top.chunk.lineEnd} '
      '(score ${top.similarity.toStringAsFixed(3)})';
}

String _buildComparisonSummary(
  Map<String, workflow.IngestionResult> results,
  List<QuerySpec> querySpecs,
  int topK, {
  RetrievalBenchmarkReport? benchmarkReport,
}) {
  final buffer = StringBuffer('# Comparison Summary\n\n');
  final names = results.keys.toList()..sort();
  final queries = uniqueQueryTexts(querySpecs);

  if (benchmarkReport != null) {
    _writeRetrievalEvaluationSummary(buffer, benchmarkReport);
  }

  if (results.length < 2) {
    buffer.writeln('Only one embedder run; nothing to compare.');
  } else {
    buffer.writeln('| Embedder A | Embedder B | Avg Overlap | Avg Score Δ |');
    buffer.writeln('|------------|------------|--------------|-------------|');

    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final a = results[names[i]]!;
        final b = results[names[j]]!;
        final overlap = _averageOverlap(a, b, queries, topK);
        final scoreDelta = _averageScoreDelta(a, b, queries, topK);
        buffer.writeln(
          '| ${names[i]} | ${names[j]} | ${(overlap * 100).toStringAsFixed(1)}% | ${scoreDelta.toStringAsFixed(3)} |',
        );
      }
    }
    buffer.writeln('');
  }

  buffer.writeln('Top results per embedder:\n');
  for (final name in names) {
    final ingestion = results[name]!;
    buffer
      ..writeln('### ${name.toUpperCase()}')
      ..writeln('- Chunks persisted: ${ingestion.chunks.length}')
      ..writeln('- Embeddings persisted: ${ingestion.embeddings.length}')
      ..writeln('- Duplicate chunks skipped: ${ingestion.duplicateIds.length}');
    if (ingestion.searchResultsByQuery.isEmpty) {
      buffer.writeln('- Search results: _none_');
    } else {
      for (final entry in ingestion.searchResultsByQuery.entries) {
        final query = entry.key;
        final resultsForQuery = entry.value.take(min(topK, entry.value.length));
        buffer.writeln('  - Query "$query":');
        for (var i = 0; i < resultsForQuery.length; i++) {
          final result = resultsForQuery.elementAt(i);
          buffer.writeln(
            '    • #${i + 1} ${result.similarity.toStringAsFixed(3)} ${result.chunk.sourcePath}:${result.chunk.lineStart}-${result.chunk.lineEnd}',
          );
        }
      }
    }
    buffer.writeln('');
  }

  return buffer.toString();
}

RetrievalBenchmarkReport _buildBenchmarkReport({
  required Map<String, workflow.IngestionResult> results,
  required RelevanceJudgments judgments,
  workflow.FixtureSpanRelevance? spanRelevance,
  required List<QuerySpec> querySpecs,
  required Map<String, String>? queryGroupsById,
  required Directory fixturesDir,
  required int topK,
}) {
  final evaluationJudgments = spanRelevance?.toJudgments() ?? judgments;
  final queryTextById = {for (final query in querySpecs) query.id: query.text};
  final names = results.keys.toList()..sort();
  final runs = <RetrievalRunSummary>[];
  for (final name in names) {
    final ingestion = results[name]!;
    final rankedByQuery = <String, List<String>>{};
    for (final queryId in evaluationJudgments.queryIds) {
      final queryText = queryTextById[queryId] ?? queryId;
      final queryResults =
          ingestion.searchResultsByQuery[queryText] ?? const <SearchResult>[];
      rankedByQuery[queryId] = spanRelevance == null
          ? queryResults
                .map(
                  (result) =>
                      workflow.stableFixtureChunkId(result.chunk, fixturesDir),
                )
                .toList(growable: false)
          : spanRelevance.rankedChunkIdsFor(
              queryId: queryId,
              results: queryResults,
              fixturesDir: fixturesDir,
            );
    }
    final evaluation = RetrievalEvaluator.evaluate(
      judgments: evaluationJudgments,
      rankedChunkIdsByQuery: rankedByQuery,
      k: topK,
    );
    runs.add(
      RetrievalRunSummary(
        name: name,
        queryCount: evaluation.queryCount,
        metrics: evaluation.average,
        queryEvaluations: evaluation.queries,
        queryGroupSummaries: queryGroupsById == null
            ? const []
            : RetrievalEvaluator.summarizeGroups(
                queryEvaluations: evaluation.queries,
                groupByQueryId: queryGroupsById,
              ),
      ),
    );
  }
  return RetrievalBenchmarkReport(k: topK, runs: runs);
}

void _writeRetrievalEvaluationSummary(
  StringBuffer buffer,
  RetrievalBenchmarkReport report,
) {
  buffer
    ..writeln('## Retrieval Evaluation @${report.k}\n')
    ..writeln(
      '| Embedder | Queries | Recall@${report.k} | nDCG@${report.k} | MRR |',
    )
    ..writeln('|----------|---------|------------|----------|-----|');

  for (final run in report.runs) {
    final metrics = run.metrics;
    buffer.writeln(
      '| ${run.name} | ${run.queryCount} | ${metrics.recall.toStringAsFixed(3)} | ${metrics.ndcg.toStringAsFixed(3)} | ${metrics.mrr.toStringAsFixed(3)} |',
    );
  }
  buffer.writeln('');

  final hasQueryGroups = report.runs.any(
    (run) => run.queryGroupSummaries.isNotEmpty,
  );
  if (!hasQueryGroups) {
    return;
  }

  buffer
    ..writeln('## Retrieval Evaluation By Query Group @${report.k}\n')
    ..writeln(
      '| Embedder | Group | Queries | Recall@${report.k} | nDCG@${report.k} | MRR |',
    )
    ..writeln('|----------|-------|---------|------------|----------|-----|');

  for (final run in report.runs) {
    for (final group in run.queryGroupSummaries) {
      final metrics = group.metrics;
      buffer.writeln(
        '| ${run.name} | ${group.name} | ${group.queryCount} | ${metrics.recall.toStringAsFixed(3)} | ${metrics.ndcg.toStringAsFixed(3)} | ${metrics.mrr.toStringAsFixed(3)} |',
      );
    }
  }
  buffer.writeln('');
}

double _averageOverlap(
  workflow.IngestionResult a,
  workflow.IngestionResult b,
  List<String> queries,
  int topK,
) {
  final relevantQueries = _queriesWithResults(a, b, queries);
  if (relevantQueries.isEmpty) return 0.0;

  var total = 0.0;
  for (final query in relevantQueries) {
    final idsA = a.searchResultsByQuery[query]!
        .take(topK)
        .map((r) => r.chunk.id)
        .toSet();
    final idsB = b.searchResultsByQuery[query]!
        .take(topK)
        .map((r) => r.chunk.id)
        .toSet();
    if (idsA.isEmpty && idsB.isEmpty) {
      total += 1.0;
    } else if (idsA.isEmpty || idsB.isEmpty) {
      total += 0.0;
    } else {
      final intersection = idsA.intersection(idsB).length.toDouble();
      final union = idsA.union(idsB).length.toDouble();
      total += union == 0 ? 0.0 : intersection / union;
    }
  }
  return total / relevantQueries.length;
}

double _averageScoreDelta(
  workflow.IngestionResult a,
  workflow.IngestionResult b,
  List<String> queries,
  int topK,
) {
  final relevantQueries = _queriesWithResults(a, b, queries);
  if (relevantQueries.isEmpty) return 0.0;

  var totalDelta = 0.0;
  var observations = 0;
  for (final query in relevantQueries) {
    final mapB = {
      for (final result in b.searchResultsByQuery[query]!.take(topK))
        result.chunk.id: result.similarity,
    };
    for (final result in a.searchResultsByQuery[query]!.take(topK)) {
      final otherScore = mapB[result.chunk.id];
      if (otherScore != null) {
        totalDelta += (result.similarity - otherScore).abs();
        observations += 1;
      }
    }
  }
  return observations == 0 ? 0.0 : totalDelta / observations;
}

List<String> _queriesWithResults(
  workflow.IngestionResult a,
  workflow.IngestionResult b,
  Iterable<String> queries,
) {
  return queries
      .where(
        (query) =>
            a.searchResultsByQuery.containsKey(query) &&
            b.searchResultsByQuery.containsKey(query),
      )
      .toList();
}
