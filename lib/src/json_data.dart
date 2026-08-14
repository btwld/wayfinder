Map<String, Object?> deepUnmodifiableJsonMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(
      value.map(
        (key, item) => MapEntry<String, Object?>(
          key,
          _deepUnmodifiableJsonValue(item),
        ),
      ),
    );

Object? _deepUnmodifiableJsonValue(Object? value) {
  if (value is Map<String, Object?>) {
    return deepUnmodifiableJsonMap(value);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(
      value.map<Object?>(_deepUnmodifiableJsonValue),
    );
  }
  return value;
}
