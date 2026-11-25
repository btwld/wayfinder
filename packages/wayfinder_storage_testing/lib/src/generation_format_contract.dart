import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

import 'generation_format_harness.dart';
import 'store_support.dart';

/// A repeatable, model-free workload of 400 passages, 40 queries and filters.
final class SyntheticGenerationCorpus {
  SyntheticGenerationCorpus({int seed = 20261125}) {
    final random = math.Random(seed);
    Float32List vector() => Float32List.fromList(
      List.generate(dimension, (_) => random.nextDouble() * 2 - 1),
    );
    passages = List.generate(400, (_) => vector());
    queries = List.generate(40, (_) => vector());
    final ordinals = List.generate(passages.length, (index) => index)
      ..shuffle(random);
    half = ordinals.take(200).toSet();
    sparse = ordinals.skip(200).take(20).toSet();
  }

  static const dimension = 384;
  late final List<Float32List> passages;
  late final List<Float32List> queries;
  late final Set<int> half;
  late final Set<int> sparse;
}

/// Registers bit-preserving storage and filtered nearest-row contract tests.
void runGenerationFormatContract(GenerationFormatHarness harness) {
  final format = harness.format;
  group('${format.name} generation format', () {
    const record = 'Opaque text: ñ, 蝶, \u0000, and CRLF\r\n';
    late Directory temp;
    late Directory folder;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-format-');
      folder = await Directory(p.join(temp.path, 'generation')).create();
    });
    tearDown(() => temp.delete(recursive: true));

    test(
      'preserves record and bits, ordinal order and requested order',
      () async {
        final rows = List.generate(
          1000,
          (index) => Uint32List.fromList([
            0x80000000,
            1,
            0x80000001,
            0x3f800000 + index,
          ]).buffer.asFloat32List(),
        );
        await format.write(folder, GenerationData(record, rows, dimension: 4));
        final before = await treeBytes(folder);
        expect(before.keys.toSet(), harness.files);
        final reader = await format.open(folder);
        try {
          expect(await reader.record(), record);
          expect(await reader.rowCount(), 1000);
          expect((await reader.vectors()).map(_bits), rows.map(_bits));
          const selected = [999, 0, 547, 0, 2];
          expect(
            (await reader.rows(selected)).map(_bits),
            selected.map((index) => _bits(rows[index])),
          );
          expect(await reader.rows([]), isEmpty);
        } finally {
          await reader.close();
        }
        expect(await treeBytes(folder), before);
      },
    );

    test('stores an empty generation', () async {
      await format.write(
        folder,
        const GenerationData(record, [], dimension: 384),
      );
      final reader = await format.open(folder);
      try {
        expect(await reader.record(), record);
        expect(await reader.rowCount(), 0);
        expect(await reader.vectors(), isEmpty);
        expect(await reader.nearest(Float32List(384), 10), isEmpty);
      } finally {
        await reader.close();
      }
    });

    for (final target in ['marker', 'data file', 'folder']) {
      if (target == 'data file' && harness.files.length == 1) continue;
      test('removed $target is GenerationGone', () async {
        await format.write(
          folder,
          GenerationData(record, [
            Float32List.fromList([1]),
          ], dimension: 1),
        );
        if (target == 'folder') {
          await folder.delete(recursive: true);
        } else if (target == 'marker') {
          await harness.marker(folder).delete();
        } else {
          await File(
            p.join(
              folder.path,
              harness.files.firstWhere((name) => name != format.marker),
            ),
          ).delete();
        }
        await expectLater(format.open(folder), throwsA(isA<GenerationGone>()));
      });
    }

    test('corrupt content is not GenerationGone', () async {
      await format.write(
        folder,
        GenerationData(record, [
          Float32List.fromList([1]),
        ], dimension: 1),
      );
      final dataFile = harness.files.firstWhere(
        (name) => name != format.marker,
        orElse: () => format.marker,
      );
      await File(p.join(folder.path, dataFile)).writeAsBytes([0, 1, 2]);
      await expectLater(() async {
        final reader = await format.open(folder);
        try {
          await reader.vectors();
        } finally {
          await reader.close();
        }
      }, throwsA(isNot(isA<GenerationGone>())));
    });

    test(
      '40 queries match exact cosine with all, 50% and 5% allowed',
      () async {
        final corpus = SyntheticGenerationCorpus();
        await format.write(
          folder,
          GenerationData(
            record,
            corpus.passages,
            dimension: SyntheticGenerationCorpus.dimension,
          ),
        );
        final before = await treeBytes(folder);
        final reader = await format.open(folder);
        try {
          for (final (index, query) in corpus.queries.indexed) {
            for (final allowed in [null, corpus.half, corpus.sparse]) {
              final eligible =
                  allowed ??
                  Set.of(Iterable<int>.generate(corpus.passages.length));
              for (final count in [10, 30]) {
                final rows = await reader.nearest(
                  query,
                  count,
                  allowed: allowed,
                );
                final reason =
                    'query $index; ${eligible.length} allowed; count $count';
                expect(
                  rows,
                  hasLength(math.min(count, eligible.length)),
                  reason: reason,
                );
                expect(
                  rows.map((row) => row.ordinal).toSet(),
                  hasLength(rows.length),
                  reason: reason,
                );
                expect(
                  rows.every((row) => eligible.contains(row.ordinal)),
                  isTrue,
                  reason: reason,
                );
                final scored = [
                  for (final row in rows)
                    (row.ordinal, _cosine(query, row.vector)),
                ];
                for (final row in rows) {
                  expect(
                    _bits(row.vector),
                    _bits(corpus.passages[row.ordinal]),
                    reason: reason,
                  );
                }
                final expected = [
                  for (final ordinal in eligible)
                    (ordinal, _cosine(query, corpus.passages[ordinal])),
                ]..sort((left, right) => right.$2.compareTo(left.$2));
                expect(scored, expected.take(count), reason: reason);
              }
            }
          }
          expect(
            await reader.nearest(corpus.queries.first, 5, allowed: {}),
            isEmpty,
          );
        } finally {
          await reader.close();
        }
        expect(await treeBytes(folder), before);
      },
    );

    test('returns both rows one float32 step apart', () async {
      final rows = [
        Uint32List.fromList([0x3f800000, 0x3f800001]).buffer.asFloat32List(),
        Float32List.fromList([1, 1]),
      ];
      await format.write(folder, GenerationData(record, rows, dimension: 2));
      final reader = await format.open(folder);
      try {
        final near = await reader.nearest(Float32List.fromList([1, 0]), 2);
        expect(near.map((row) => row.ordinal), [1, 0]);
        expect(near.map((row) => _bits(row.vector)), rows.reversed.map(_bits));
      } finally {
        await reader.close();
      }
    });
  });
}

List<int> _bits(Float32List row) =>
    row.buffer.asUint32List(row.offsetInBytes, row.length);

double _cosine(Float32List query, Float32List row) {
  var dot = 0.0;
  var queryNorm = 0.0;
  var rowNorm = 0.0;
  for (var index = 0; index < row.length; index++) {
    dot += query[index] * row[index];
    queryNorm += query[index] * query[index];
    rowNorm += row[index] * row[index];
  }
  return dot / (math.sqrt(queryNorm) * math.sqrt(rowNorm));
}
