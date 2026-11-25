import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../util/similarity.dart';
import 'generation.dart';
import 'generation_format.dart';

/// The original Wayfinder `snapshot.json` and `vectors.f32` generation.
final class PlainFileGenerationFormat implements GenerationFormat {
  const PlainFileGenerationFormat();

  @override
  String get name => 'plain-file';

  @override
  String get marker => IndexGeneration.snapshotFile;

  @override
  Future<void> write(Directory staged, GenerationData data) async {
    final dimension = data.dimension ?? data.vectors.first.length;
    await File(p.join(staged.path, IndexGeneration.vectorsFile)).writeAsBytes(
      IndexGeneration.encode(data.vectors, dimension),
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

/// Attaches detached, already verified rows only to a plain-file reader.
void usePlainFileVerifiedRows(GenerationReader reader, List<Float32List> rows) {
  if (reader is _PlainFileReader) reader._verified = rows;
}

final class _PlainFileReader
    implements GenerationReader, GenerationRowDimensions {
  _PlainFileReader(this._record, this._file, this._count, this.dimension);

  static const _bulkReadDivisor = 4;

  final String _record;
  final RandomAccessFile _file;
  final int _count;
  @override
  final int dimension;
  List<Float32List>? _verified;

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

  @override
  Future<List<Float32List>> vectors() => _read(0, _count);

  @override
  Future<List<Float32List>> rows(List<int> ordinals) async {
    final cached = _verified;
    return [
      for (final ordinal in ordinals)
        cached != null
            ? cached[ordinal]
            : (await _read(
                RangeError.checkValueInInterval(ordinal, 0, _count - 1),
                1,
              )).single,
    ];
  }

  @override
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  }) async {
    final cached = _verified;
    if (allowed == null ||
        allowed.length * _bulkReadDivisor >= _count ||
        cached != null) {
      return exactNearestRows(
        cached ?? await vectors(),
        query,
        count,
        allowed: allowed,
      );
    }
    final ordinals = allowed.toList();
    final selected = await rows(ordinals);
    return [
      for (final row in exactNearestRows(selected, query, count))
        NearRow(ordinals[row.ordinal], row.vector),
    ];
  }

  @override
  Future<void> close() => _file.close();
}

/// Reference exact cosine scan. Equal scores break by ordinal.
/// The returned vectors are the original rows, not copies or native scores.
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
