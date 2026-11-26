import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/storage_driver.dart' show cosineSimilarity;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'src/metric_baseline.dart';

/// Evaluates each component against fixed, passage-level judgments. Run the
/// development split before selecting defaults; inspect held-out results later.
///
/// `knowledge/*` runs search through [KnowledgeIndex], which scores stored
/// vectors exactly in Dart. `findSimilar/*` runs query the same vectors through
/// the store's own [BaseStore.findSimilar], without scope or policy, and
/// compare each result list with exact cosine ranking.
Future<void> main(List<String> args) => evaluate(args);

/// Result-list cutoff of the `findSimilar/*` runs.
const findSimilarLimit = 10;

const _gatedMetrics = ['recall', 'mrr', 'exactRecall'];

Future<void> evaluate(
  List<String> args, {
  Map<String, FutureOr<BaseStore> Function(String)> additionalStores = const {},
  String fixture = 'fixtures/okf_retrieval',
}) async {
  final stores = <String, FutureOr<BaseStore> Function(String)>{
    'memory': (_) => MemoryStore(),
    ...additionalStores,
  };
  final parser = ArgParser()
    ..addMultiOption(
      'split',
      allowed: ['development', 'held_out'],
      defaultsTo: ['development'],
    )
    ..addOption('output', mandatory: true)
    ..addOption('stores', defaultsTo: stores.keys.join(','))
    ..addOption(
      'baselines',
      help: 'Directory of <store>.json baselines to check against.',
    )
    ..addFlag(
      'update-baselines',
      negatable: false,
      help: 'Write the measured values to --baselines instead of checking.',
    )
    ..addFlag('timing', defaultsTo: true, help: 'Measure warm query latency.');
  final options = parser.parse(args);
  if (options.rest.isNotEmpty) {
    throw ArgumentError('Unexpected positional arguments.');
  }
  final measureTiming = options.flag('timing');
  final splits = options.multiOption('split');
  final selectedStores = options.option('stores')!.split(',');
  if (selectedStores.any((kind) => !stores.containsKey(kind))) {
    throw ArgumentError('--stores accepts ${stores.keys.join(',')}');
  }
  final baselines = options.option('baselines');
  if (options.flag('update-baselines') && baselines == null) {
    throw ArgumentError('--update-baselines requires --baselines.');
  }
  final queryText = await File('$fixture/queries.json').readAsString();
  final data = jsonDecode(queryText) as Map<String, Object?>;
  final queries = {
    for (final split in splits)
      split: (data['queries']! as List)
          .cast<Map<String, Object?>>()
          .where((row) => row['split'] == split)
          .toList(),
  };
  final snapshot = await KnowledgeSnapshot.load(
    '$fixture/bundle',
    bundleId: 'evaluation',
  );
  final governors = (data['governingSources']! as Map).cast<String, String>();
  final date = DateTime.parse(data['asOf']! as String);
  final limit = data['limit']! as int;
  final passes = measureTiming ? 3 : 1;
  final directory = await Directory.systemTemp.createTemp('okf_evaluation');
  LlamaEmbedder? embedder;
  final report = <String, Object?>{};
  try {
    final loading = Stopwatch()..start();
    embedder = await LlamaEmbedder.open();
    report.addAll({
      'splits': {for (final split in splits) split: queries[split]!.length},
      'querySha256': sha256.convert(utf8.encode(queryText)).toString(),
      'conceptCount': snapshot.conceptPaths.length,
      'model': embedder.modelName,
      'modelOpenMs': loading.elapsedMicroseconds / 1000,
      'limit': limit,
      'findSimilarLimit': findSimilarLimit,
      'asOf': data['asOf'],
      'timing': measureTiming
          ? 'JIT, warm query vectors; first pass excluded; two measured passes'
          : 'Disabled; correctness results only',
    });
    final runs = <String, Map<String, Map<String, Object?>>>{};
    for (final kind in selectedStores) {
      final storeRuns = {
        for (final split in splits) split: <String, Object?>{},
      };
      for (final contextual in [false, true]) {
        final store = await stores[kind]!(
          p.join(directory.path, '$kind-$contextual'),
        );
        try {
          final index = KnowledgeIndex(
            store: store,
            embedder: embedder,
            includeContext: contextual,
            countTokens: embedder.countTokens,
            maxTokens: embedder.model.maxTokens,
          );
          final building = Stopwatch()..start();
          final sync = await index.synchronize(snapshot);
          final syncMs = building.elapsedMicroseconds / 1000;
          final chunks = (await store.getStats())['chunks'];
          final model = index.embeddingModelName;
          final vectors = await store.getEmbeddingsForChunks(
            snapshot.chunks.map((chunk) => chunk.id).toSet(),
            source: embedder.sourceName,
            modelName: model,
          );
          final passages = {
            for (final chunk in snapshot.chunks) chunk.id: chunk,
          };
          for (final split in splits) {
            for (final config in _configs.where(
              (config) => config.context == contextual,
            )) {
              final rows = <Map<String, Object?>>[];
              final times = <double>[];
              for (var pass = 0; pass < passes; pass++) {
                for (final row in queries[split]!) {
                  final history = row['history'] == true;
                  final policy = KnowledgeSearchPolicy(
                    currentOnly: config.lifecycle && !history,
                    asOf: date,
                    statuses: history ? {OkfLifecycleStatus.deprecated} : null,
                    pathPrefixes:
                        (row['scope'] as List?)?.cast<String>().toSet() ?? {},
                    governingSources: config.authority ? governors : {},
                    expandRelationships: config.links,
                  );
                  final watch = Stopwatch()..start();
                  final response = await index.search(
                    row['query']! as String,
                    limit: limit,
                    contextLimit: limit,
                    policy: policy,
                  );
                  if (pass > 0) times.add(watch.elapsedMicroseconds / 1000);
                  if (pass != 0) continue;
                  for (final hit in response.context) {
                    if (!policy.allows(snapshot, hit.result.chunk.sourcePath)) {
                      throw StateError(
                        'Ineligible context leaked for ${row['id']}',
                      );
                    }
                  }
                  rows.add({
                    'id': row['id'],
                    'group': row['group'],
                    ..._judge(
                      [for (final hit in response.context) hit.result.chunk],
                      row,
                      cutoff: limit,
                    ),
                    'context': [
                      for (final hit in response.context)
                        {
                          'path': hit.result.chunk.sourcePath,
                          'lineStart': hit.result.chunk.lineStart,
                          'lineEnd': hit.result.chunk.lineEnd,
                          'content': hit.result.chunk.content,
                          'reason': hit.reason,
                          'via': hit.viaPath,
                          'edgeOrigin': hit.edge?.origin.wireValue,
                        },
                    ],
                    'matches': response.matches
                        .map((hit) => hit.chunk.sourcePath)
                        .toList(),
                    'notices': [
                      for (final notice in response.notices) notice.text,
                    ],
                  });
                }
              }
              storeRuns[split]!['knowledge/${config.name}'] = _run(
                rows,
                times,
                syncMs: syncMs,
                embeddedChunks: sync.embeddedChunks,
                chunks: chunks,
              );
              stdout.writeln(
                '$kind $split knowledge/${config.name}: ${_metrics(rows)}',
              );
            }
            final rows = <Map<String, Object?>>[];
            final times = <double>[];
            final queryVectors = [
              for (final row in queries[split]!)
                await embedder.generateQueryVector(row['query']! as String),
            ];
            for (var pass = 0; pass < passes; pass++) {
              for (final (i, row) in queries[split]!.indexed) {
                final query = queryVectors[i];
                final watch = Stopwatch()..start();
                final hits = await store.findSimilar(
                  query,
                  embedder.sourceName,
                  model,
                  limit: findSimilarLimit,
                );
                if (pass > 0) times.add(watch.elapsedMicroseconds / 1000);
                if (pass != 0) continue;
                final exact = {
                  for (final vector in vectors)
                    vector.chunkId: cosineSimilarity(query, vector.vector),
                };
                final expected = exact.keys.toList()
                  ..sort((a, b) {
                    final byScore = exact[b]!.compareTo(exact[a]!);
                    if (byScore != 0) return byScore;
                    final byPath = passages[a]!.sourcePath.compareTo(
                      passages[b]!.sourcePath,
                    );
                    return byPath != 0 ? byPath : a.compareTo(b);
                  });
                final top = expected.take(findSimilarLimit).toSet();
                rows.add({
                  'id': row['id'],
                  'group': row['group'],
                  ..._judge(
                    [for (final hit in hits) hit.chunk],
                    row,
                    cutoff: findSimilarLimit,
                  ),
                  'exactRecall':
                      hits.where((hit) => top.contains(hit.chunk.id)).length /
                      top.length,
                  'maxScoreDelta': hits.fold<double>(
                    0,
                    (delta, hit) => math.max(
                      delta,
                      (hit.similarity - exact[hit.chunk.id]!).abs(),
                    ),
                  ),
                  'hits': [
                    for (final hit in hits)
                      {
                        'path': hit.chunk.sourcePath,
                        'lineStart': hit.chunk.lineStart,
                        'similarity': hit.similarity,
                        'exactRank': expected.indexOf(hit.chunk.id) + 1,
                      },
                  ],
                });
              }
            }
            final input = contextual ? 'context' : 'body';
            storeRuns[split]!['findSimilar/$input'] = _run(
              rows,
              times,
              syncMs: syncMs,
              embeddedChunks: sync.embeddedChunks,
              chunks: chunks,
            );
            stdout.writeln(
              '$kind $split findSimilar/$input: ${_metrics(rows)}',
            );
          }
        } finally {
          await store.close();
        }
      }
      runs[kind] = storeRuns;
    }
    report['runs'] = runs;
    final output = File(options.option('output')!);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    if (baselines != null) {
      for (final kind in selectedStores) {
        final file = File(p.join(baselines, '$kind.json'));
        final current = _gated(report, runs[kind]!);
        if (options.flag('update-baselines')) {
          await writeBaseline(file, current, identity: _identity);
          stdout.writeln('Updated ${file.path}');
        } else {
          final failures = compareWithBaseline(
            jsonDecode(await file.readAsString()) as Map<String, Object?>,
            current,
            identity: _identity,
          );
          for (final failure in failures) {
            stderr.writeln('$kind $failure');
          }
          if (failures.isNotEmpty) exitCode = 1;
        }
      }
    }
  } finally {
    await embedder?.dispose();
    await directory.delete(recursive: true);
  }
}

const _configs = [
  (
    name: 'body',
    context: false,
    lifecycle: false,
    authority: false,
    links: false,
  ),
  (
    name: 'context',
    context: true,
    lifecycle: false,
    authority: false,
    links: false,
  ),
  (
    name: 'lifecycle',
    context: false,
    lifecycle: true,
    authority: false,
    links: false,
  ),
  (
    name: 'authority',
    context: false,
    lifecycle: false,
    authority: true,
    links: false,
  ),
  (
    name: 'relationships',
    context: false,
    lifecycle: false,
    authority: false,
    links: true,
  ),
  (
    name: 'combined_no_links',
    context: true,
    lifecycle: true,
    authority: true,
    links: false,
  ),
  (
    name: 'combined',
    context: true,
    lifecycle: true,
    authority: true,
    links: true,
  ),
];

/// Judges [ranked] against the query's supports. A passage is relevant when
/// it contains a support that no earlier passage contained.
Map<String, Object?> _judge(
  List<Chunk> ranked,
  Map<String, Object?> query, {
  required int cutoff,
}) {
  final supports = (query['support']! as List).cast<Map<String, Object?>>();
  if (supports.isEmpty) {
    return {'top1': null, 'recall': null, 'rr': null, 'ndcg': null};
  }
  double gain(int rank) => math.ln2 / math.log(rank + 1);
  final found = <Map<String, Object?>>{};
  int? first;
  var dcg = 0.0;
  for (final (i, chunk) in ranked.take(cutoff).indexed) {
    final matched = supports.where(
      (support) =>
          chunk.sourcePath == support['path'] &&
          chunk.content.contains(support['contains']! as String),
    );
    if (matched.isEmpty) continue;
    first ??= i + 1;
    if (found.containsAll(matched)) continue;
    found.addAll(matched);
    dcg += gain(i + 1);
  }
  var ideal = 0.0;
  for (var rank = 1; rank <= math.min(supports.length, cutoff); rank++) {
    ideal += gain(rank);
  }
  return {
    'top1': first == 1,
    'recall': found.length / supports.length,
    'rr': first == null ? 0.0 : 1 / first,
    'ndcg': dcg / ideal,
  };
}

Map<String, Object?> _run(
  List<Map<String, Object?>> rows,
  List<double> times, {
  required double syncMs,
  required int embeddedChunks,
  required Object? chunks,
}) {
  times.sort();
  return {
    'aggregate': _metrics(rows),
    'groups': {
      for (final group in rows.map((row) => row['group']! as String).toSet())
        group: _metrics(rows.where((row) => row['group'] == group).toList()),
    },
    'queryP50Ms': times.isEmpty ? null : times[(times.length * .5).floor()],
    'queryP95Ms': times.isEmpty ? null : times[(times.length * .95).floor()],
    'syncMs': syncMs,
    'embeddedChunks': embeddedChunks,
    'chunks': chunks,
    'queries': rows,
  };
}

Map<String, Object?> _metrics(List<Map<String, Object?>> rows) {
  final judged = rows.where((row) => row['recall'] != null).toList();
  double? mean(List<Map<String, Object?>> rows, String key) => rows.isEmpty
      ? null
      : rows.fold<double>(0, (sum, row) => sum + (row[key]! as num)) /
            rows.length;
  final exact = rows.first.containsKey('exactRecall');
  return {
    'answerable': judged.length,
    'top1Correct': judged.where((row) => row['top1'] == true).length,
    'top1': judged.isEmpty
        ? null
        : judged.where((row) => row['top1'] == true).length / judged.length,
    'recall': mean(judged, 'recall'),
    'mrr': mean(judged, 'rr'),
    'ndcg': mean(judged, 'ndcg'),
    if (exact) ...{
      'exactRecall': mean(rows, 'exactRecall'),
      'maxScoreDelta': rows.fold<double>(
        0,
        (delta, row) => math.max(delta, row['maxScoreDelta']! as double),
      ),
    } else
      'unanswerableCandidates': rows
          .where((row) => row['recall'] == null)
          .fold<int>(0, (sum, row) => sum + (row['context']! as List).length),
  };
}

const _identity = ['model', 'querySha256'];

/// The gated metrics of [runs], keyed by split and run.
Map<String, Object?> _gated(
  Map<String, Object?> report,
  Map<String, Map<String, Object?>> runs,
) => {
  for (final key in _identity) key: report[key],
  for (final MapEntry(key: split, value: named) in runs.entries)
    split: {
      for (final MapEntry(key: name, value: run) in named.entries)
        name: {
          for (final metric in _gatedMetrics)
            if (((run! as Map<String, Object?>)['aggregate']!
                    as Map<String, Object?>)[metric]
                case final num value)
              metric: value,
        },
    },
};
