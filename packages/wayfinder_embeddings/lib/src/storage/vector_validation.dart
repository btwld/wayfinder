import '../util/checks.dart';

/// Validates a vector passed into a storage search boundary.
void validateQueryVector(List<double> vector) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, 'queryVector', 'must not be empty');
  }

  for (final (index, value) in vector.indexed) {
    checkFinite(value, 'queryVector[$index]');
  }
}

/// Validates an optional embedding source/model identity filter.
void validateEmbeddingIdentityFilter(String? value, String name) {
  if (value != null) {
    checkNotBlank(value, name);
  }
}

/// Prevents a replacement from removing a chunk that it is also writing.
void validateReplacementIds(
  Iterable<String> writtenIds,
  Set<String> removedIds,
) {
  for (final id in removedIds) {
    checkNotBlank(id, 'removeChunkIds');
  }
  if (writtenIds.any(removedIds.contains)) {
    throw ArgumentError('Written and removed chunk IDs must be disjoint.');
  }
}
