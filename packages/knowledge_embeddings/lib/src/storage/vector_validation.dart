/// Validates a vector passed into a storage search boundary.
void validateQueryVector(List<double> vector) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, 'queryVector', 'must not be empty');
  }

  for (var index = 0; index < vector.length; index++) {
    final value = vector[index];
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'queryVector[$index]', 'must be finite');
    }
  }
}

/// Validates an optional embedding source/model identity filter.
void validateEmbeddingIdentityFilter(String? value, String name) {
  if (value != null && value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
}

/// Validates a required storage identity value such as a chunk ID.
void validateRequiredStorageIdentity(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
}
