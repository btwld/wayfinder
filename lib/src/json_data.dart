/// Recursively copies [source] into an unmodifiable JSON-compatible map.
///
/// Values that are neither maps nor lists are shared with [source] rather
/// than copied.
///
/// This mirrors okf's private `lib/src/json_data.dart` helper, which okf does
/// not export; keep the two files identical.
Map<String, Object?> deepUnmodifiableJsonMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(
      source.map(
        (key, value) =>
            MapEntry<String, Object?>(key, _deepUnmodifiable(value)),
      ),
    );

Object? _deepUnmodifiable(Object? value) {
  if (value is Map<String, Object?>) {
    return deepUnmodifiableJsonMap(value);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
  }
  return value;
}
