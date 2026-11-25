import 'dart:math' as math;
import 'dart:typed_data';

/// Canonical little-endian float32 storage, with cosine-domain validation.
Uint8List encodeFloat32(List<double> vector) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, 'vector', 'must not be empty');
  }
  final bytes = Uint8List(vector.length * 4);
  final data = ByteData.sublistView(bytes);
  var nonzero = false;
  for (var i = 0; i < vector.length; i++) {
    data.setFloat32(i * 4, vector[i], Endian.little);
    final stored = data.getFloat32(i * 4, Endian.little);
    if (!stored.isFinite) {
      throw ArgumentError.value(
        vector[i],
        'vector[$i]',
        'must remain finite as float32',
      );
    }
    nonzero |= stored != 0;
  }
  if (!nonzero) {
    throw ArgumentError.value(
      vector,
      'vector',
      'must remain nonzero as float32',
    );
  }
  return bytes;
}

Float32List decodeFloat32(Uint8List bytes, int dimension) {
  if (dimension <= 0 || bytes.length != dimension * 4) {
    throw const FormatException('Invalid vector byte length.');
  }
  final data = ByteData.sublistView(bytes);
  final vector = Float32List(dimension);
  var nonzero = false;
  for (var i = 0; i < dimension; i++) {
    final value = data.getFloat32(i * 4, Endian.little);
    if (!value.isFinite) {
      throw const FormatException('Nonfinite stored vector.');
    }
    nonzero |= value != 0;
    vector[i] = value;
  }
  if (!nonzero) throw const FormatException('Zero stored vector.');
  return vector;
}

// With a maximum component between 2^-24 and 2^24, the float32 dot and
// squared norms cannot overflow at vec0's maximum of 8192 dimensions. Even
// dropping every subnormal product contributes less than a rounding unit
// relative to the minimum norm product (2^-48).
bool hasBoundedCosineScale(List<double> vector) {
  final scale = vectorScale(vector);
  return scale >= 1 / (1 << 24) && scale <= (1 << 24);
}

double vectorScale(List<double> vector) {
  var scale = 0.0;
  for (final value in vector) {
    scale = math.max(scale, value.abs());
  }
  return scale;
}

Uint8List scaleFloat32(List<double> vector, double scale) =>
    encodeFloat32([for (final value in vector) value / scale]);
