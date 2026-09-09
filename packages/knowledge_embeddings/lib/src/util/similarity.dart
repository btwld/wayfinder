import 'dart:math';

/// Computes cosine similarity between two vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  _validateSimilarityVectors(a, b);

  double dotProd = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dotProd += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0.0 || normB == 0.0) {
    return 0.0;
  }
  return dotProd / (sqrt(normA) * sqrt(normB));
}

void _validateSimilarityVectors(List<double> a, List<double> b) {
  _validateSimilarityVector(a, 'a');
  _validateSimilarityVector(b, 'b');

  if (a.length != b.length) {
    throw ArgumentError.value(
      b.length,
      'b',
      'must have the same dimension as a (${a.length})',
    );
  }
}

void _validateSimilarityVector(List<double> vector, String name) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, name, 'must not be empty');
  }

  for (var index = 0; index < vector.length; index++) {
    final value = vector[index];
    if (!value.isFinite) {
      throw ArgumentError.value(value, '$name[$index]', 'must be finite');
    }
  }
}
