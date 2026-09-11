/// Builds the failure for one metadata violation.
///
/// The two entry points differ only in the exception they raise: constructor
/// arguments raise [ArgumentError], `fromMap` parsing raises [FormatException].
typedef _MetadataErrorFactory =
    Object Function(String requirement, Object? value);

const String _jsonCompatibleRequirement =
    'values must be JSON-compatible: null, bool, string, finite number, map, '
    'list, or set';

/// Returns a deep unmodifiable copy of [metadata], rejecting invalid entries.
///
/// [name] is the argument name reported in the [ArgumentError].
Map<String, Object?> freezeMetadataMap(
  Map<String, Object?> metadata, {
  required String name,
}) {
  Object error(String requirement, Object? value) =>
      ArgumentError.value(value, name, requirement);

  return Map<String, Object?>.unmodifiable({
    for (final entry in metadata.entries)
      _metadataKey(entry.key, error): _metadataValue(entry.value, error),
  });
}

/// Reads [metadata] from a serialized map, rejecting invalid entries.
///
/// [context] and [fieldName] build the `<context>: '<fieldName>'` prefix of the
/// [FormatException].
Map<String, Object?> readMetadataMap(
  Map<Object?, Object?> metadata, {
  required String context,
  required String fieldName,
}) {
  Object error(String requirement, Object? value) =>
      FormatException("$context: '$fieldName' $requirement, got $value");

  return {
    for (final entry in metadata.entries)
      _metadataKey(entry.key, error): _metadataValue(entry.value, error),
  };
}

/// Returns a mutable, JSON-ready copy of [metadata].
Map<String, Object?> metadataMapSnapshot(Map<String, Object?> metadata) {
  return {
    for (final entry in metadata.entries)
      entry.key: _metadataValueSnapshot(entry.value),
  };
}

String _metadataKey(Object? key, _MetadataErrorFactory error) {
  if (key is! String) {
    throw error('keys must be String', key);
  }
  if (key.trim().isEmpty) {
    throw error('keys must not be blank', key);
  }
  return key;
}

Object? _metadataValue(Object? value, _MetadataErrorFactory error) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw error('numeric values must be finite', value);
    }
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        _metadataKey(entry.key, error): _metadataValue(entry.value, error),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((entry) => _metadataValue(entry, error)),
    );
  }
  if (value is Set) {
    return List<Object?>.unmodifiable(
      value.map((entry) => _metadataValue(entry, error)),
    );
  }
  throw error(_jsonCompatibleRequirement, value);
}

Object? _metadataValueSnapshot(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key as String: _metadataValueSnapshot(entry.value),
    };
  }
  if (value is List) {
    return value.map(_metadataValueSnapshot).toList();
  }
  if (value is Set) {
    return value.map(_metadataValueSnapshot).toList();
  }
  return value;
}
