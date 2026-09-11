import 'dart:convert';
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:path/path.dart' as p;

/// Compares storage with precomputed vectors from a dense comparison run.
///
/// Run in the package directory, after installing ObjectBox:
/// `dart run tool/benchmark_stores.dart path/to/dense output.json`.
/// Input decoding and model inference are outside the measured intervals.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: benchmark_stores.dart DENSE_ARTIFACT_DIR OUTPUT',
    );
  }
  List<Map<String, Object?>> readRows(String name) =>
      (jsonDecode(File(p.join(args[0], name)).readAsStringSync()) as List)
          .cast<Map<String, Object?>>();
  final chunks = readRows('chunks.json').map(Chunk.fromMap).toList();
  final embeddings = readRows(
    'embeddings.json',
  ).map(Embedding.fromMap).toList();
  final queries = readRows('queries.json');
  if (chunks.isEmpty || embeddings.isEmpty || queries.isEmpty) {
    throw StateError('A completed dense run with query vectors is required.');
  }
  final identity = embeddings.first;
  final directory = await Directory.systemTemp.createTemp('store_benchmark');
  final results = <String, Object?>{};
  try {
    for (final kind in ['memory', 'objectbox']) {
      final db = p.join(directory.path, kind);
      final watch = Stopwatch()..start();
      BaseStore store = kind == 'memory' ? MemoryStore() : ObjectBoxStore(db);
      final openMs = _ms(watch);
      try {
        watch.reset();
        await store.storeBatch(chunks: chunks, embeddings: embeddings);
        final writeMs = _ms(watch);
        double? reopenMs;
        if (kind == 'objectbox') {
          await store.close();
          watch.reset();
          store = ObjectBoxStore(db);
          reopenMs = _ms(watch);
        }
        watch.reset();
        final persistedChunks = await store.getAllChunks();
        final readChunksMs = _ms(watch);
        watch.reset();
        final lexical = BM25LexicalIndex.fromChunks(persistedChunks);
        final lexicalBuildMs = _ms(watch);
        final lexicalMs = <double>[];
        final denseMs = <double>[];
        // Two full warmup passes, then ten measured passes over all queries.
        for (var pass = 0; pass < 12; pass++) {
          for (final row in queries) {
            final vector = (row['vector'] as List)
                .cast<num>()
                .map((value) => value.toDouble())
                .toList();
            watch.reset();
            final lexicalHits = lexical.search(
              row['query'] as String,
              limit: 10,
            );
            final lexicalElapsed = _ms(watch);
            watch.reset();
            final denseHits = await store.findSimilar(
              vector,
              identity.source,
              identity.modelName,
              limit: 10,
            );
            final denseElapsed = _ms(watch);
            if (lexicalHits.isEmpty || denseHits.isEmpty) {
              throw StateError(
                'Benchmark query unexpectedly returned no hits.',
              );
            }
            if (pass >= 2) {
              lexicalMs.add(lexicalElapsed);
              denseMs.add(denseElapsed);
            }
          }
        }
        results[kind] = {
          'openMs': openMs,
          'writeMs': writeMs,
          'reopenMs': ?reopenMs,
          'readChunksMs': readChunksMs,
          'bm25BuildMs': lexicalBuildMs,
          'bm25SearchMs': _summary(lexicalMs),
          'denseSearchMs': _summary(denseMs),
          'minimumSearchCandidates': kind == 'objectbox' ? 50 : null,
        };
      } finally {
        await store.close();
      }
      if (kind == 'objectbox') {
        (results[kind] as Map<String, Object?>)['databaseBytes'] = await File(
          p.join(db, 'data.mdb'),
        ).length();
      }
    }
    final report = {
      'sdk': Platform.version,
      'os': Platform.operatingSystem,
      'chunks': chunks.length,
      'dimensions': identity.vector.length,
      'queries': queries.length,
      'warmupPasses': 2,
      'measuredPasses': 10,
      'results': results,
    };
    final output = File(args[1]);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln('Store measurements: ${output.path}');
  } finally {
    await directory.delete(recursive: true);
  }
}

double _ms(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

Map<String, double> _summary(List<double> samples) {
  samples.sort();
  return {
    'p50': samples[(samples.length * 0.5).ceil() - 1],
    'p95': samples[(samples.length * 0.95).ceil() - 1],
  };
}
