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

/// Prevents a replacement from removing a chunk that it is also writing.
void validateReplacementIds(
  Iterable<String> writtenIds,
  Set<String> removedIds,
) {
  for (final id in removedIds) {
    validateRequiredStorageIdentity(id, 'removeChunkIds');
  }
  if (writtenIds.any(removedIds.contains)) {
    throw ArgumentError('Written and removed chunk IDs must be disjoint.');
  }
}
