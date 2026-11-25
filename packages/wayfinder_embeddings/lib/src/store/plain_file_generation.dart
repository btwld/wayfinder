import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../util/similarity.dart';
import 'generation.dart';
import 'generation_format.dart';

/// The default format: a `snapshot.json` record and a `vectors.f32` file.
final class PlainFileGenerationFormat implements GenerationFormat {
  const PlainFileGenerationFormat();

  @override
  String get name => 'plain-file';

  @override
  String get marker => IndexGeneration.snapshotFile;

  @override
  Future<void> write(Directory staged, GenerationData data) async {
    await File(p.join(staged.path, IndexGeneration.vectorsFile)).writeAsBytes(
      IndexGeneration.encode(data.vectors, data.dimension),
      flush: true,
    );
    await File(
      p.join(staged.path, marker),
    ).writeAsString(data.record, flush: true);
  }

  @override
  Future<GenerationReader> open(Directory generation) async {
    RandomAccessFile? file;
    try {
      final record = await File(p.join(generation.path, marker)).readAsString();
      file = await File(
        p.join(generation.path, IndexGeneration.vectorsFile),
      ).open();
      final header = IndexGeneration.inspectHeader(
        await file.read(IndexGeneration.headerBytes),
        await file.length(),
      );
      return _PlainFileReader(record, file, header.count, header.dimension);
    } on FileSystemException {
      await file?.close();
      throw const GenerationGone();
    } catch (_) {
      await file?.close();
      rethrow;
    }
  }
}

final class _PlainFileReader implements GenerationReader {
  _PlainFileReader(this._record, this._file, this._count, this.dimension);

  /// A filter that allows at least a quarter of the rows reads the whole file.
  static const _bulkReadDivisor = 4;

  final String _record;
  final RandomAccessFile _file;
  final int _count;
  @override
  final int dimension;
  Future<List<Float32List>>? _all;

  @override
  Future<String> record() async => _record;

  @override
  Future<int> rowCount() async => _count;

  Future<List<Float32List>> _read(int start, int count) async {
    final width = dimension * 4;
    try {
      await _file.setPosition(IndexGeneration.headerBytes + start * width);
      final bytes = await _file.read(count * width);
      if (bytes.length != count * width) {
        throw const FormatException('The vectors file has the wrong size.');
      }
      return IndexGeneration.decodeRows(bytes, dimension);
    } on FileSystemException {
      throw const GenerationGone();
    }
  }

  /// Read once per reader: the core may ask again while it widens a search.
  @override
  Future<List<Float32List>> vectors() => _all ??= _read(0, _count);

  /// Reads each run of consecutive ordinals with one call.
  @override
  Future<List<Float32List>> rows(List<int> ordinals) async {
    for (final ordinal in ordinals) {
      RangeError.checkValueInInterval(ordinal, 0, _count - 1);
    }
    if (_all case final all?) {
      final loaded = await all;
      return [for (final ordinal in ordinals) loaded[ordinal]];
    }
    final sorted = ordinals.toSet().toList()..sort();
    final found = <int, Float32List>{};
    for (var index = 0; index < sorted.length;) {
      var end = index + 1;
      while (end < sorted.length && sorted[end] == sorted[end - 1] + 1) {
        end++;
      }
      final run = await _read(sorted[index], end - index);
      for (var offset = 0; offset < run.length; offset++) {
        found[sorted[index + offset]] = run[offset];
      }
      index = end;
    }
    return [for (final ordinal in ordinals) found[ordinal]!];
  }

  @override
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  }) async {
    if (allowed == null ||
        allowed.length * _bulkReadDivisor >= _count ||
        _all != null) {
      return exactNearestRows(await vectors(), query, count, allowed: allowed);
    }
    final ordinals = allowed.toList()..sort();
    final selected = await rows(ordinals);
    return [
      for (final row in exactNearestRows(selected, query, count))
        NearRow(ordinals[row.ordinal], row.vector),
    ];
  }

  @override
  Future<void> close() => _file.close();
}

/// Returns the [count] rows of [vectors] nearest to [query] by exact cosine
/// similarity, best first, with equal scores in ordinal order.
///
/// When [allowed] is not null, only those ordinals are eligible. The
/// returned rows are the given rows, not copies. Drivers can use this scan
/// as a reference in tests.
List<NearRow> exactNearestRows(
  List<Float32List> vectors,
  Float32List query,
  int count, {
  Set<int>? allowed,
}) {
  if (count < 0) throw RangeError.value(count, 'count');
  if (count == 0) return [];
  final ranked =
      [
        for (final ordinal in allowed ?? Iterable<int>.generate(vectors.length))
          (ordinal: ordinal, score: cosineSimilarity(query, vectors[ordinal])),
      ]..sort((left, right) {
        final score = right.score.compareTo(left.score);
        return score != 0 ? score : left.ordinal.compareTo(right.ordinal);
      });
  return [
    for (var index = 0; index < math.min(count, ranked.length); index++)
      NearRow(ranked[index].ordinal, vectors[ranked[index].ordinal]),
  ];
}
