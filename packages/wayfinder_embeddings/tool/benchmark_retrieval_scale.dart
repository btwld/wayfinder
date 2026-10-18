import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:wayfinder_embeddings/src/util/similarity.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'benchmark_retrieval.dart' show elapsed, summarize;

/// Synthetic storage/ranking stress only; no model or semantic quality claims.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('SIZE OUTPUT');
  final size = int.parse(args[0]);
  if (size <= 0) throw ArgumentError.value(size, 'SIZE', 'must be positive');
  final random = Random(91307);
  final chunks = [
    for (var i = 0; i < size; i++)
      Chunk(
        id: 'scale-$i',
        sourcePath: 'generated/item-$i.md',
        lineStart: 1,
        lineEnd: 1,
        content:
            'Record $i describes processing operation ${i % 173} for partition ${i % 97}.',
        type: 'text',
      ),
  ];
  final vectors = [
    for (final chunk in chunks)
      Embedding(
        chunkId: chunk.id,
        source: 'synthetic',
        modelName: 'seed-91307',
        vector: List.generate(384, (_) => random.nextDouble() - .5),
      ),
  ];
  final ids = chunks.map((chunk) => chunk.id).toSet();
  final byId = {for (final chunk in chunks) chunk.id: chunk};
  final directory = await Directory.systemTemp.createTemp('retrieval_scale');
  final results = <String, Object?>{};
  try {
    for (final kind in ['memory', 'objectbox']) {
      final path = '${directory.path}/$kind';
      final store = kind == 'memory'
          ? MemoryStore()
          : ObjectBoxStore.open(path);
      try {
        final clock = Stopwatch()..start();
        await store.storeBatch(chunks: chunks, embeddings: vectors);
        final writeMs = elapsed(clock);
        final denseTimings = <double>[];
        final firstIds = <String>[];
        for (var pass = 0; pass < 4; pass++) {
          for (var q = 0; q < 10; q++) {
            final target = (q * 997) % size;
            clock.reset();
            final loaded = await store.getEmbeddingsForChunks(
              ids,
              source: 'synthetic',
              modelName: 'seed-91307',
            );
            final dense = [
              for (final vector in loaded)
                SearchResult(
                  chunk: byId[vector.chunkId]!,
                  embedding: vector,
                  similarity: cosineSimilarity(
                    vectors[target].vector,
                    vector.vector,
                  ),
                ),
            ];
            dense.sort((a, b) => b.similarity.compareTo(a.similarity));
            final denseMs = elapsed(clock);
            if (dense.first.chunk.id != chunks[target].id) {
              throw StateError('Exact lookup lost target');
            }
            if (pass > 0) denseTimings.add(denseMs);
            if (pass == 0) firstIds.add(dense.first.chunk.id);
          }
        }
        var databaseBytes = 0;
        if (await Directory(path).exists()) {
          await for (final file in Directory(path).list(recursive: true)) {
            if (file is File) databaseBytes += await file.length();
          }
        }
        results[kind] = {
          'writeMs': writeMs,
          'databaseBytes': databaseBytes,
          'timings': {'dense': summarize(denseTimings)},
          'exactTargets': firstIds,
          'processPeakRssBytes': ProcessInfo.maxRss,
        };
      } finally {
        await store.close();
      }
    }
    await File(args[1]).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'size': size, 'seed': 91307, 'vectorDimensions': 384, 'note': 'Synthetic precomputed vectors; sequential stores; shared process peak RSS; no inference', 'results': results})}\n',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
