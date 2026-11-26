import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:okf/okf.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'src/benchmark_models.dart';
import 'src/metric_baseline.dart';

/// One isolated dense retrieval run. The orchestrator owns process/build timing.
Future<void> main(List<String> args) => runBenchmark(args);

Future<void> runBenchmark(
  List<String> args, {
  Map<String, BaseStore Function(String)> additionalStores = const {},
  String fixture = 'fixtures/embedding_comparison',
}) async {
  final stores = <String, BaseStore Function(String)>{
    'memory': (_) => MemoryStore(),
    ...additionalStores,
  };
  final total = Stopwatch()..start();
  final parser = ArgParser()
    ..addOption('arm', defaultsTo: 'dense', help: 'Dense retrieval only.')
    ..addOption('store', allowed: stores.keys, defaultsTo: 'memory')
    ..addOption(
      'split',
      allowed: ['development', 'test'],
      defaultsTo: 'development',
    )
    ..addOption('fixture', defaultsTo: fixture)
    ..addOption('database', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('iterations', defaultsTo: '1000')
    ..addOption(
      'model',
      allowed: benchmarkModels.keys,
      defaultsTo: localEmbeddingModel.id,
    )
    ..addOption('model-file')
    ..addOption(
      'baseline',
      help: 'Baseline file of judged metrics per split to check against.',
    )
    ..addFlag(
      'update-baseline',
      negatable: false,
      help: 'Write the measured split to --baseline instead of checking.',
    )
    ..addFlag('verify-token-budget', negatable: false);
  final options = parser.parse(args);
  final arm = options.option('arm')!;
  if (arm != 'dense') {
    throw ArgumentError(
      'This benchmark supports dense retrieval only. Use --arm=dense.',
    );
  }
  final iterations = int.parse(options.option('iterations')!);
  if (options.rest.isNotEmpty || iterations < 0) {
    throw ArgumentError('Use named options and nonnegative iterations.');
  }
  final modelSpec = benchmarkModels[options.option('model')]!;
  final modelPath = options.option('model-file');
  if (modelSpec != localEmbeddingModel && modelPath == null) {
    throw ArgumentError(
      'Experimental models require an explicit --model-file.',
    );
  }
  final baseline = options.option('baseline');
  if (options.flag('update-baseline') && baseline == null) {
    throw ArgumentError('--update-baseline requires --baseline.');
  }
  final fixturePath = options.option('fixture')!;
  final sourceText = await File('$fixturePath/sources.json').readAsString();
  final sources = (jsonDecode(sourceText) as Map<String, dynamic>)
      .cast<String, String>();
  final queryText = await File('$fixturePath/queries.json').readAsString();
  final data = jsonDecode(queryText) as Map<String, dynamic>;
  final rows = (data['queries'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((row) => row['split'] == options.option('split'))
      .toList();
  final watch = Stopwatch()..start();
  final model = await LlamaEmbedder.open(
    model: modelSpec,
    modelFile: modelPath == null ? null : File(modelPath),
  );
  final modelOpenMs = elapsed(watch);
  final encoder = MeasuredEmbedder(model);
  watch.reset();
  try {
    final store = MeasuredStore(
      stores[options.option('store')]!(options.option('database')!),
    );
    final storeOpenMs = elapsed(watch);
    try {
      watch.reset();
      final snapshot = KnowledgeSnapshot.fromSources(
        sources,
        bundleId: 'comparison',
      );
      final parseMs = elapsed(watch);
      var tokenizationMs = 0.0;
      if (options.flag('verify-token-budget')) {
        watch.reset();
        for (final chunk in snapshot.chunks) {
          if (await model.countTokens(
                snapshot.textFor(chunk, includeContext: true),
              ) >
              model.model.maxTokens) {
            throw StateError('Shared passage exceeds budget: ${chunk.id}');
          }
        }
        tokenizationMs = elapsed(watch);
      }
      KnowledgeIndex makeIndex() =>
          KnowledgeIndex(store: store, embedder: encoder, includeContext: true);
      var index = makeIndex();
      watch.reset();
      final sync = await index.synchronize(snapshot);
      final syncMs = elapsed(watch);
      final initialDocumentMs = encoder.documentMs;
      final initialWriteMs = store.writeMs;
      final initialReadMs = store.readMs;
      final governors = (data['governingSources'] as Map<String, dynamic>)
          .cast<String, String>();
      KnowledgeSearchPolicy policy(
        Map<String, dynamic> row, {
        bool context = true,
      }) => KnowledgeSearchPolicy(
        currentOnly: row['history'] != true,
        asOf: DateTime.parse(data['asOf'] as String),
        statuses: row['history'] == true
            ? {OkfLifecycleStatus.deprecated}
            : null,
        expandRelationships: context,
        governingSources: context ? governors : const {},
        secondPassageMargin: context ? knowledgeSecondPassageMargin : null,
      );
      Future<
        ({
          List<SearchResult> matches,
          KnowledgeSearchResponse context,
          double searchMs,
          double encodingMs,
        })
      >
      search(Map<String, dynamic> row) async {
        final clock = Stopwatch()..start();
        final before = encoder.queryMs;
        final context = await index.search(
          row['query'] as String,
          policy: policy(row),
          limit: 10,
          contextLimit: 10,
        );
        final searchMs = elapsed(clock);
        final encodingMs = encoder.queryMs - before;
        // The policy-free ranking reuses the cached query vector.
        final raw = (await index.search(
          row['query'] as String,
          policy: policy(row, context: false),
          limit: 10,
          contextLimit: 10,
        )).matches;
        return (
          matches: raw,
          context: context,
          searchMs: searchMs,
          encodingMs: encodingMs,
        );
      }

      final quality = <Map<String, Object?>>[];
      double? firstResultMs;
      for (final row in rows) {
        final result = await search(row);
        firstResultMs ??= elapsed(total);
        final supports = (row['support'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final context = result.context.context
            .map((hit) => hit.result)
            .toList();
        quality.add({
          'id': row['id'],
          'topic': row['topic'],
          'group': row['group'],
          'raw': judge(result.matches, supports),
          'context': judge(context, supports),
          'topSimilarity': result.matches.firstOrNull?.similarity,
          'matches': result.matches.map((hit) => hit.chunk.sourcePath).toList(),
          'passages': [
            for (final hit in result.context.context)
              {
                'path': hit.result.chunk.sourcePath,
                'line': hit.result.chunk.lineStart,
                'content': hit.result.chunk.content,
                'reason': hit.reason,
              },
          ],
        });
      }
      final random = Random(91307);
      final uncached = <double>[];
      final encoded = <double>[];
      final ranking = <double>[];
      final queryCountBefore = encoder.queries;
      // Fresh index instances clear the query cache without reloading the engine.
      // Synchronization occurs outside query intervals and must reuse all vectors.
      while (uncached.length < iterations) {
        index = makeIndex();
        final reused = await index.synchronize(snapshot);
        if (reused.embeddedChunks != 0) throw StateError('Vector reuse failed');
        final shuffled = [...rows]..shuffle(random);
        for (final row in shuffled) {
          if (uncached.length >= iterations) break;
          final result = await search(row);
          uncached.add(result.searchMs);
          encoded.add(result.encodingMs);
          ranking.add(result.searchMs - result.encodingMs);
        }
      }
      final uncachedQueryEncodings = (encoder.queries) - queryCountBefore;
      // Each split has 80 queries, below the adapter's 100-entry cache bound.
      for (var pass = 0; pass < 2; pass++) {
        for (final row in rows) {
          await search(row);
        }
      }
      final cacheBefore = encoder.queries;
      final cached = <double>[];
      while (cached.length < iterations) {
        final shuffled = [...rows]..shuffle(random);
        for (final row in shuffled) {
          if (cached.length >= iterations) break;
          final result = await search(row);
          cached.add(result.searchMs);
        }
      }
      final cachedQueryEncodings = (encoder.queries) - cacheBefore;
      if (cachedQueryEncodings != 0 || uncachedQueryEncodings != iterations) {
        throw StateError('Cache scenario did not match its label');
      }
      final updateRows = <String, Object?>{};
      final changed = {...sources};
      final firstPath = changed.keys.first;
      changed[firstPath] = changed[firstPath]!.replaceFirst(
        'type: reference',
        'type: reference\nverified: false',
      );
      watch.reset();
      final metadata = await index.synchronize(
        KnowledgeSnapshot.fromSources(changed, bundleId: 'comparison'),
      );
      updateRows['metadata'] = {
        'ms': elapsed(watch),
        'embedded': metadata.embeddedChunks,
        'written': metadata.writtenChunks,
      };
      if (metadata.embeddedChunks != 0) {
        throw StateError('Metadata change encoded vectors');
      }
      changed[firstPath] =
          '${changed[firstPath]}\nAdditional operational note.\n';
      final deletedPath = changed.keys.firstWhere(
        (path) => path.endsWith('/expired.md'),
      );
      changed.remove(deletedPath);
      watch.reset();
      final body = await index.synchronize(
        KnowledgeSnapshot.fromSources(changed, bundleId: 'comparison'),
      );
      updateRows['bodyAndDelete'] = {
        'ms': elapsed(watch),
        'embedded': body.embeddedChunks,
        'written': body.writtenChunks,
        'removed': body.removedChunks,
      };
      // Restore the original corpus, so a subsequent process measures honest reuse.
      await index.synchronize(snapshot);
      final stats = await store.getStats();
      final report = {
        'arm': arm,
        'store': options.option('store'),
        'split': options.option('split'),
        'runtime': Platform.version,
        'modelOpened': true,
        'modelIdentity': model.modelName,
        'querySha256': sha256.convert(utf8.encode(queryText)).toString(),
        'modelSpec': model.model.toMap(),
        'truncatedInputs': model.truncatedInputs,
        'passageManifestSha256': sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  for (final chunk in snapshot.chunks)
                    [chunk.id, snapshot.textFor(chunk, includeContext: true)],
                ]),
              ),
            )
            .toString(),
        'chunks': snapshot.chunks.length,
        'concepts': snapshot.conceptPaths.length,
        'modelOpenMs': modelOpenMs,
        'storeOpenMs': storeOpenMs,
        'parseMs': parseMs,
        'tokenBudgetVerificationMs': tokenizationMs,
        'syncMs': syncMs,
        'initialDocumentEncodingMs': initialDocumentMs,
        'initialWriteMs': initialWriteMs,
        'initialReadMs': initialReadMs,
        'initialEmbedded': sync.embeddedChunks,
        'timeToFirstResultMs': firstResultMs,
        'uncached': summarize(uncached),
        'queryEncoding': summarize(encoded),
        'rankingAndContext': summarize(ranking),
        'cached': summarize(cached),
        'uncachedQueryEncodings': uncachedQueryEncodings,
        'cachedQueryEncodings': cachedQueryEncodings,
        'totalDocumentEncodings': encoder.documents,
        'totalQueryEncodings': encoder.queries,
        'updates': updateRows,
        'stats': stats,
        'peakRssBytes': ProcessInfo.maxRss,
        'aggregate': {
          for (final field in ['raw', 'context'])
            field: aggregate([
              for (final row in quality) row[field]! as Map<String, Object?>,
            ]),
        },
        'quality': quality,
      };
      final output = File(options.option('output')!);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      if (baseline != null) {
        final aggregates = report['aggregate']! as Map<String, Object?>;
        final current = {
          for (final key in _identity) key: report[key],
          options.option('split')!: {
            for (final MapEntry(key: field, value: metrics)
                in aggregates.entries)
              field: {
                for (final metric in _gatedMetrics)
                  metric: (metrics! as Map<String, Object?>)[metric],
              },
          },
        };
        final file = File(baseline);
        if (options.flag('update-baseline')) {
          await writeBaseline(file, current, identity: _identity);
          stdout.writeln('Updated ${file.path}');
        } else {
          final failures = compareWithBaseline(
            jsonDecode(await file.readAsString()) as Map<String, Object?>,
            current,
            identity: _identity,
          );
          failures.forEach(stderr.writeln);
          if (failures.isNotEmpty) exitCode = 1;
        }
      }
    } finally {
      await store.close();
    }
  } finally {
    await model.dispose();
  }
}

const _identity = ['modelIdentity', 'querySha256'];

const _gatedMetrics = ['recall3', 'recall10', 'mrr'];

double elapsed(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

/// Summarizes [judgments] from [judge] for one split.
Map<String, Object?> aggregate(List<Map<String, Object?>> judgments) {
  final answerable = [
    for (final row in judgments)
      if (row['answerable'] == true) row,
  ];
  double mean(String key) =>
      answerable.fold<double>(0, (sum, row) => sum + (row[key]! as num)) /
      answerable.length;
  return {
    'answerable': answerable.length,
    'top1Correct': answerable.where((row) => row['top1'] == true).length,
    'recall3': mean('recall3'),
    'recall10': mean('recall10'),
    'mrr': mean('rr'),
    'unanswerable': judgments.length - answerable.length,
    'unanswerableWithCandidates': judgments
        .where((row) => row['answerable'] != true && row['candidates'] != 0)
        .length,
  };
}

Map<String, Object?> summarize(List<double> values) {
  if (values.isEmpty) return {'count': 0};
  final sorted = [...values]..sort();
  return {
    'count': sorted.length,
    'p50Ms': sorted[(sorted.length * .5).floor()],
    'p95Ms': sorted[(sorted.length * .95).floor()],
    'totalMs': sorted.reduce((a, b) => a + b),
  };
}

Map<String, Object?> judge(
  List<SearchResult> hits,
  List<Map<String, dynamic>> supports,
) {
  final ranks = <int>[];
  for (var i = 0; i < hits.length; i++) {
    if (supports.any(
      (support) =>
          hits[i].chunk.sourcePath == support['path'] &&
          hits[i].chunk.content.contains(support['contains'] as String),
    )) {
      ranks.add(i + 1);
    }
  }
  double recall(int k) =>
      supports
          .where(
            (support) => hits
                .take(k)
                .any(
                  (hit) =>
                      hit.chunk.sourcePath == support['path'] &&
                      hit.chunk.content.contains(support['contains'] as String),
                ),
          )
          .length /
      supports.length;
  return {
    'answerable': supports.isNotEmpty,
    'top1': ranks.contains(1),
    'recall3': supports.isEmpty ? null : recall(3),
    'recall10': supports.isEmpty ? null : recall(10),
    'rr': supports.isEmpty
        ? null
        : ranks.isEmpty
        ? 0.0
        : 1 / ranks.first,
    'candidates': hits.length,
  };
}

class MeasuredEmbedder extends BaseEmbedder {
  MeasuredEmbedder(this.delegate);
  final BaseEmbedder delegate;
  int documents = 0;
  int queries = 0;
  double documentMs = 0;
  double queryMs = 0;
  @override
  String get sourceName => delegate.sourceName;
  @override
  String get modelName => delegate.modelName;
  @override
  int get dimension => delegate.dimension;
  @override
  Future<List<double>> generateEmbedding(String text) async =>
      (await generateEmbeddings([text])).single;
  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final watch = Stopwatch()..start();
    final result = await delegate.generateEmbeddings(texts);
    documentMs += elapsed(watch);
    documents += texts.length;
    return result;
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    final watch = Stopwatch()..start();
    final result = await delegate.generateQueryVector(text);
    queryMs += elapsed(watch);
    queries++;
    return result;
  }
}

class MeasuredStore extends BaseStore {
  MeasuredStore(this.delegate);
  final BaseStore delegate;
  double readMs = 0;
  double writeMs = 0;
  @override
  Future<String> storeChunk(Chunk chunk) => delegate.storeChunk(chunk);
  @override
  Future<void> storeEmbedding(Embedding embedding) =>
      delegate.storeEmbedding(embedding);
  @override
  Future<Chunk?> getChunk(String id) => delegate.getChunk(id);
  @override
  Future<Embedding?> getEmbedding(
    String id, {
    String? source,
    String? modelName,
  }) => delegate.getEmbedding(id, source: source, modelName: modelName);
  @override
  Future<List<Chunk>> getAllChunks() async {
    final watch = Stopwatch()..start();
    final result = await delegate.getAllChunks();
    readMs += elapsed(watch);
    return result;
  }

  @override
  Future<List<Embedding>> getAllEmbeddings() => delegate.getAllEmbeddings();
  @override
  Future<List<Embedding>> getEmbeddingsForChunks(
    Set<String> ids, {
    required String source,
    required String modelName,
  }) async {
    final watch = Stopwatch()..start();
    final result = await delegate.getEmbeddingsForChunks(
      ids,
      source: source,
      modelName: modelName,
    );
    readMs += elapsed(watch);
    return result;
  }

  @override
  Future<void> replaceChunks({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Set<String> removeChunkIds,
  }) async {
    final watch = Stopwatch()..start();
    await delegate.replaceChunks(
      chunks: chunks,
      embeddings: embeddings,
      removeChunkIds: removeChunkIds,
    );
    writeMs += elapsed(watch);
  }

  @override
  Future<List<SearchResult>> findSimilar(
    List<double> vector,
    String source,
    String modelName, {
    int limit = 5,
  }) => delegate.findSimilar(vector, source, modelName, limit: limit);
  @override
  Future<void> deleteChunk(String id) => delegate.deleteChunk(id);
  @override
  Future<void> deleteEmbedding(String id) => delegate.deleteEmbedding(id);
  @override
  Future<Map<String, Object?>> getStats() => delegate.getStats();
  @override
  Future<void> close() => delegate.close();
}
