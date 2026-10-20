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
Map<String, Object?> metadataMapSnapshot(Map<String, Object?> metadata) => {
  for (final entry in metadata.entries)
    entry.key: _metadataValueSnapshot(entry.value),
};

String _metadataKey(Object? key, _MetadataErrorFactory error) => switch (key) {
  final String key when key.trim().isNotEmpty => key,
  final String key => throw error('keys must not be blank', key),
  _ => throw error('keys must be String', key),
};

Object? _metadataValue(Object? value, _MetadataErrorFactory error) =>
    switch (value) {
      null || String() || bool() => value,
      final num value when value.isFinite => value,
      final num value => throw error('numeric values must be finite', value),
      final Map<Object?, Object?> value => Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          _metadataKey(entry.key, error): _metadataValue(entry.value, error),
      }),
      final List<Object?> value => List<Object?>.unmodifiable(
        value.map((entry) => _metadataValue(entry, error)),
      ),
      final Set<Object?> value => List<Object?>.unmodifiable(
        value.map((entry) => _metadataValue(entry, error)),
      ),
      _ => throw error(_jsonCompatibleRequirement, value),
    };

Object? _metadataValueSnapshot(Object? value) => switch (value) {
  final Map<Object?, Object?> value => {
    for (final entry in value.entries)
      entry.key as String: _metadataValueSnapshot(entry.value),
  },
  final List<Object?> value => value.map(_metadataValueSnapshot).toList(),
  final Set<Object?> value => value.map(_metadataValueSnapshot).toList(),
  _ => value,
};
