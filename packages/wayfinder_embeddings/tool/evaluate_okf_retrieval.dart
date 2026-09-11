import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Evaluates each component against fixed, passage-level judgments. Run the
/// development split before selecting defaults; inspect held-out results later.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'split',
      allowed: ['development', 'held_out'],
      defaultsTo: 'development',
    )
    ..addOption('output', mandatory: true)
    ..addOption('stores', defaultsTo: 'memory,objectbox')
    ..addFlag('native', negatable: false)
    ..addFlag('timing', defaultsTo: true, help: 'Measure warm query latency.');
  final options = parser.parse(args);
  if (options.rest.isNotEmpty) {
    throw ArgumentError('Unexpected positional arguments.');
  }
  final measureTiming = options.flag('timing');
  final stores = options.option('stores')!.split(',');
  if (stores.any((kind) => !['memory', 'objectbox'].contains(kind))) {
    throw ArgumentError('--stores accepts memory,objectbox');
  }
  final queryText = await File(
    'fixtures/okf_retrieval/queries.json',
  ).readAsString();
  final data = jsonDecode(queryText) as Map<String, Object?>;
  final queries = (data['queries']! as List)
      .cast<Map<String, Object?>>()
      .where((row) => row['split'] == options.option('split'))
      .toList();
  final snapshot = await KnowledgeSnapshot.load(
    'fixtures/okf_retrieval/bundle',
    bundleId: 'evaluation',
  );
  final governors = (data['governingSources']! as Map).cast<String, String>();
  final date = DateTime.parse(data['asOf']! as String);
  final limit = data['limit']! as int;
  final directory = await Directory.systemTemp.createTemp('okf_evaluation');
  LlamaEmbedder? embedder;
  final report = <String, Object?>{};
  try {
    final loading = Stopwatch()..start();
    if (options.flag('native')) embedder = await LlamaEmbedder.open();
    report.addAll({
      'split': options.option('split'),
      'queryCount': queries.length,
      'querySha256': sha256.convert(utf8.encode(queryText)).toString(),
      'conceptCount': snapshot.conceptPaths.length,
      'model': embedder?.modelName,
      'modelOpenMs': loading.elapsedMicroseconds / 1000,
      'limit': limit,
      'asOf': data['asOf'],
      'timing': measureTiming
          ? 'JIT, warm query vectors; first pass excluded; two measured passes'
          : 'Disabled; correctness results only',
    });
    final runs = <String, Object?>{};
    for (final kind in stores) {
      final storeRuns = <String, Object?>{};
      for (final contextual in [false, true]) {
        final BaseStore store = kind == 'memory'
            ? MemoryStore()
            : ObjectBoxStore(p.join(directory.path, '$kind-$contextual'));
        try {
          final index = KnowledgeIndex(
            store: store,
            embedder: embedder,
            includeContext: contextual,
            countTokens: embedder?.countTokens,
            maxTokens: embedder?.model.maxTokens,
          );
          final building = Stopwatch()..start();
          final sync = await index.synchronize(snapshot);
          final syncMs = building.elapsedMicroseconds / 1000;
          for (final config in const [
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
          ].where((config) => config.context == contextual)) {
            for (final mode in KnowledgeRetrievalMode.values.where(
              (mode) => embedder != null || mode == KnowledgeRetrievalMode.bm25,
            )) {
              final rows = <Map<String, Object?>>[];
              final times = <double>[];
              for (var pass = 0; pass < (measureTiming ? 3 : 1); pass++) {
                for (final row in queries) {
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
                    mode: mode,
                    limit: limit,
                    contextLimit: limit,
                    policy: policy,
                  );
                  if (pass > 0) times.add(watch.elapsedMicroseconds / 1000);
                  if (pass != 0) continue;
                  final supports = (row['support']! as List)
                      .cast<Map<String, Object?>>();
                  bool supportsClaim(
                    KnowledgeContextHit hit,
                    Map<String, Object?> support,
                  ) =>
                      hit.result.chunk.sourcePath == support['path'] &&
                      hit.result.chunk.content.contains(
                        support['contains']! as String,
                      );
                  final relevantRanks = <int>[
                    for (var i = 0; i < response.context.length; i++)
                      if (supports.any(
                        (support) =>
                            supportsClaim(response.context[i], support),
                      ))
                        i + 1,
                  ];
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
                    'top1': supports.isEmpty ? null : relevantRanks.contains(1),
                    'recall': supports.isEmpty
                        ? null
                        : supports
                                  .where(
                                    (support) => response.context.any(
                                      (hit) => supportsClaim(hit, support),
                                    ),
                                  )
                                  .length /
                              supports.length,
                    'rr': supports.isEmpty
                        ? null
                        : relevantRanks.isEmpty
                        ? 0.0
                        : 1 / relevantRanks.first,
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
                    'notices': response.notices,
                  });
                }
              }
              times.sort();
              storeRuns['${config.name}/${mode.name}'] = {
                'aggregate': _metrics(rows),
                'groups': {
                  for (final group
                      in rows.map((row) => row['group']! as String).toSet())
                    group: _metrics(
                      rows.where((row) => row['group'] == group).toList(),
                    ),
                },
                'queryP50Ms': measureTiming
                    ? times[(times.length * .5).floor()]
                    : null,
                'queryP95Ms': measureTiming
                    ? times[(times.length * .95).floor()]
                    : null,
                'syncMs': syncMs,
                'embeddedChunks': sync.embeddedChunks,
                'chunks': (await store.getStats())['chunks'],
                'queries': rows,
              };
              stdout.writeln(
                '$kind ${config.name}/${mode.name}: ${_metrics(rows)}',
              );
            }
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
  } finally {
    await embedder?.dispose();
    await directory.delete(recursive: true);
  }
}

Map<String, Object?> _metrics(List<Map<String, Object?>> rows) {
  final judged = rows.where((row) => row['recall'] != null).toList();
  return {
    'answerable': judged.length,
    'top1Correct': judged.where((row) => row['top1'] == true).length,
    'recall': judged.isEmpty
        ? null
        : judged.fold<double>(0, (sum, row) => sum + (row['recall']! as num)) /
              judged.length,
    'mrr': judged.isEmpty
        ? null
        : judged.fold<double>(0, (sum, row) => sum + (row['rr']! as num)) /
              judged.length,
    'unanswerableCandidates': rows
        .where((row) => row['recall'] == null)
        .fold<int>(0, (sum, row) => sum + (row['context']! as List).length),
  };
}
