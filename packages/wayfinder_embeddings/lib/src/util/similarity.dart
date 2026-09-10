import 'dart:math';

/// Computes cosine similarity between two vectors.
///
/// Finite vectors are scaled before accumulation to avoid overflow and
/// underflow. A zero vector has similarity zero.
double cosineSimilarity(List<double> a, List<double> b) {
  final scaleA = _validateSimilarityVector(a, 'a');
  final scaleB = _validateSimilarityVector(b, 'b');
  if (a.length != b.length) {
    throw ArgumentError.value(
      b.length,
      'b',
      'must have the same dimension as a (${a.length})',
    );
  }
  if (scaleA == 0 || scaleB == 0) return 0;

  double dotProd = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final valueA = a[i] / scaleA;
    final valueB = b[i] / scaleB;
    dotProd += valueA * valueB;
    normA += valueA * valueA;
    normB += valueB * valueB;
  }
  return (dotProd / (sqrt(normA) * sqrt(normB))).clamp(-1.0, 1.0);
}

double _validateSimilarityVector(List<double> vector, String name) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, name, 'must not be empty');
  }

  var scale = 0.0;
  for (var index = 0; index < vector.length; index++) {
    final value = vector[index];
    if (!value.isFinite) {
      throw ArgumentError.value(value, '$name[$index]', 'must be finite');
    }
    scale = max(scale, value.abs());
  }
  return scale;
}
