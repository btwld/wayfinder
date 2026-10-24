import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The files of one index generation, and the vectors file's format.
///
/// A generation is a directory that never changes once it is published:
/// `snapshot.json`, the record of what was indexed, and `vectors.f32`, one
/// embedding per snapshot chunk in the snapshot's chunk order. The vectors
/// file starts with a 16-byte header, the ASCII magic `WFVF32\0\x01`, then
/// the dimension and the row count as little-endian unsigned 32-bit
/// integers, followed by the rows as little-endian IEEE 754 float32 values.
/// The record names the file's dimension, row count and SHA-256, so a reader
/// detects a truncated, replaced or mismatched file before it scores.
abstract final class IndexGeneration {
  /// The record of a generation.
  static const snapshotFile = 'snapshot.json';

  /// The embeddings of a generation.
  static const vectorsFile = 'vectors.f32';

  /// The value of the record's `vectors.format`.
  static const format = 'f32-v1';

  static const _headerBytes = 16;
  static final _magic = Uint8List.fromList([...ascii.encode('WFVF32'), 0, 1]);

  /// [rows] as a vectors file. Every row must have [dimension] values that
  /// stay finite as float32, and at least one that stays nonzero, so that
  /// cosine scoring is defined.
  static Uint8List encode(List<List<double>> rows, int dimension) {
    if (dimension <= 0) {
      throw ArgumentError.value(dimension, 'dimension', 'must be positive');
    }
    final bytes = Uint8List(_headerBytes + rows.length * dimension * 4);
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, _magic.length, _magic);
    data.setUint32(8, dimension, Endian.little);
    data.setUint32(12, rows.length, Endian.little);
    var offset = _headerBytes;
    for (final (index, row) in rows.indexed) {
      if (row.length != dimension) {
        throw ArgumentError.value(
          row.length,
          'rows[$index].length',
          'must be $dimension',
        );
      }
      var nonzero = false;
      for (final value in row) {
        data.setFloat32(offset, value, Endian.little);
        final stored = data.getFloat32(offset, Endian.little);
        if (!stored.isFinite) {
          throw ArgumentError.value(
            value,
            'rows[$index]',
            'must remain finite as float32',
          );
        }
        nonzero |= stored != 0;
        offset += 4;
      }
      if (!nonzero) {
        throw ArgumentError.value(row, 'rows[$index]', 'must be nonzero');
      }
    }
    return bytes;
  }

  /// The rows of a vectors file whose record says it holds [count] rows of
  /// [dimension] values with the SHA-256 [checksum]. Throws a
  /// [FormatException] when the bytes are not that file.
  static List<Float32List> decode(
    Uint8List bytes, {
    required int dimension,
    required int count,
    required String checksum,
  }) {
    if (dimension <= 0 ||
        count < 0 ||
        bytes.length != _headerBytes + dimension * count * 4) {
      throw const FormatException('The vectors file has the wrong size.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('The vectors file has no f32-v1 header.');
      }
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(8, Endian.little) != dimension ||
        data.getUint32(12, Endian.little) != count) {
      throw const FormatException(
        'The vectors file does not match its record.',
      );
    }
    if (digest(bytes) != checksum) {
      throw const FormatException('The vectors file failed its checksum.');
    }
    final width = dimension * 4;
    if (Endian.host == Endian.little) {
      // A float32 view needs its start aligned to four bytes.
      final aligned = bytes.offsetInBytes % 4 == 0
          ? bytes
          : Uint8List.fromList(bytes);
      return [
        for (var row = 0; row < count; row++)
          Float32List.sublistView(
            aligned,
            _headerBytes + row * width,
            _headerBytes + (row + 1) * width,
          ),
      ];
    }
    return [
      for (var row = 0; row < count; row++)
        Float32List.fromList([
          for (var i = 0; i < dimension; i++)
            data.getFloat32(_headerBytes + row * width + i * 4, Endian.little),
        ]),
    ];
  }

  /// The SHA-256 of [bytes], in lowercase hexadecimal.
  static String digest(List<int> bytes) => sha256.convert(bytes).toString();
}
