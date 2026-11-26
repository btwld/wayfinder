import 'dart:math' as math;
import 'dart:typed_data';

import 'checks.dart';

/// Returns the largest magnitude in [vector], or zero for a zero vector.
///
/// Throws [ArgumentError] when [vector] is empty or has a nonfinite value.
double vectorScale(List<double> vector, [String name = 'vector']) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, name, 'must not be empty');
  }
  var scale = 0.0;
  for (final (index, value) in vector.indexed) {
    checkFinite(value, '$name[$index]');
    scale = math.max(scale, value.abs());
  }
  return scale;
}

/// Returns [vector] as little-endian float32 bytes.
///
/// Throws [ArgumentError] unless every value stays finite and one stays
/// nonzero as float32, so cosine scoring is defined.
Uint8List encodeFloat32(List<double> vector, [String name = 'vector']) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, name, 'must not be empty');
  }
  final bytes = Uint8List(vector.length * 4);
  writeFloat32(ByteData.sublistView(bytes), 0, vector, name);
  return bytes;
}

/// Writes [vector] into [data] at [offset], validated as by [encodeFloat32].
void writeFloat32(
  ByteData data,
  int offset,
  List<double> vector, [
  String name = 'vector',
]) {
  var nonzero = false;
  for (final (index, value) in vector.indexed) {
    final position = offset + index * 4;
    data.setFloat32(position, value, Endian.little);
    final stored = data.getFloat32(position, Endian.little);
    if (!stored.isFinite) {
      throw ArgumentError.value(
        value,
        '$name[$index]',
        'must remain finite as float32',
      );
    }
    nonzero |= stored != 0;
  }
  if (!nonzero) {
    throw ArgumentError.value(vector, name, 'must remain nonzero as float32');
  }
}
