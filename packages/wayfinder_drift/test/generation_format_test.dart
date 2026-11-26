import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wayfinder_drift/wayfinder_drift.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  const format = SqliteGenerationFormat();
  const harness = GenerationFormatHarness(format, files: {'index.sqlite'});
  runGenerationFormatContract(harness);
  runGenerationRankingParity(format);
  runGenerationRandomParity(format, retainEncoder: true);
  runKnowledgeStoreSuites(harness);

  Future<GenerationReader> store(List<Float32List> rows) async {
    final directory = await Directory.systemTemp.createTemp('wayfinder-vec-');
    addTearDown(() => directory.delete(recursive: true));
    await format.write(directory, GenerationData('record', rows, dimension: 2));
    final reader = await format.open(directory);
    addTearDown(reader.close);
    return reader;
  }

  test('requests over 4096 rank all allowed rows exactly', () async {
    final vectors = [
      for (var i = 0; i < 8400; i++)
        Float32List.fromList([1, 8400 - i.toDouble()]),
    ];
    final query = Float32List.fromList([1, 0]);
    final reader = await store(vectors);
    final allowed = {for (var i = 0; i < vectors.length; i += 2) i};
    final actual = await reader.nearest(query, 4100, allowed: allowed);
    final expected = exactNearestRows(vectors, query, 4100, allowed: allowed);
    expect(actual.map((r) => r.ordinal), expected.map((r) => r.ordinal));
    expect(actual.map((r) => r.vector), expected.map((r) => r.vector));
  });

  test(
    'native cutoff ties can hide the best row beyond the extra candidates',
    () async {
      final rows = [
        for (var i = 0; i < 1100; i++)
          Float32List.fromList([
            1,
            1 + (i.isEven ? 1 : -1) * 0.00000011920928955078125,
          ]),
      ];
      final reader = await store(rows);
      final query = Float32List.fromList([1, 0]);
      expect(
        (await reader.nearest(query, 3)).map((r) => r.ordinal),
        exactNearestRows(rows, query, 3).map((r) => r.ordinal),
      );
    },
  );

  test('extreme float32 scales and zero queries use exact cosine', () async {
    final rows = [
      Float32List.fromList([0, 0]),
      Float32List.fromList([1e-40, 0]),
      Float32List.fromList([0, 1e38]),
      Float32List.fromList([-1, 0]),
    ];
    final reader = await store(rows);
    for (final query in [
      Float32List.fromList([1, 0]),
      Float32List(2),
      Float32List.fromList([1e38, 1e-40]),
    ]) {
      expect(
        (await reader.nearest(query, 3)).map((r) => r.ordinal),
        exactNearestRows(rows, query, 3).map((r) => r.ordinal),
      );
    }
  });
}
