/// One validation vocabulary for the package.
///
/// Constructor and method arguments use the `check*` helpers, which throw
/// [ArgumentError] with the argument name. `fromMap` parsing uses the `read*`
/// helpers, which throw [FormatException] prefixed with
/// `<Context>.fromMap: '<field>'`.
library;

/// Throws unless [value] holds a non-whitespace character.
String checkNotBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}

/// Throws unless [value] is greater than zero.
T checkPositive<T extends num>(T value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be greater than zero');
  }
  return value;
}

/// Throws unless [value] is zero or greater.
T checkNonNegative<T extends num>(T value, String name) {
  if (value < 0) {
    throw ArgumentError.value(
      value,
      name,
      'must be greater than or equal to zero',
    );
  }
  return value;
}

/// Throws unless [value] is a finite number.
double checkFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
  return value;
}

/// Throws unless [value] is longer than zero.
Duration checkPositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be greater than zero');
  }
  return value;
}

/// Reads a String at [key], rejecting a missing, mistyped, or blank value.
///
/// Pass `allowBlank: true` to accept a blank string.
String readString(
  Map<String, Object?> map,
  String key, {
  required String context,
  bool allowBlank = false,
}) => switch (map[key]) {
  final String value when allowBlank || value.trim().isNotEmpty => value,
  final String value => throw formatFieldError(
    context,
    key,
    'must not be blank',
    value,
  ),
  final value => throw formatFieldError(
    context,
    key,
    'must be a String',
    value,
  ),
};

/// Reads an int at [key], rejecting a missing or mistyped value.
int readInt(Map<String, Object?> map, String key, {required String context}) =>
    switch (map[key]) {
      final int value => value,
      final value => throw formatFieldError(
        context,
        key,
        'must be an int',
        value,
      ),
    };

/// Reads a double at [key], accepting any finite number.
double readDouble(
  Map<String, Object?> map,
  String key, {
  required String context,
}) => switch (map[key]) {
  final num value => value.toDouble(),
  final value => throw formatFieldError(
    context,
    key,
    'must be a number',
    value,
  ),
};

/// Reads a map at [key], rejecting a missing or mistyped value.
Map<Object?, Object?> readMap(
  Map<String, Object?> map,
  String key, {
  required String context,
}) => switch (map[key]) {
  final Map<Object?, Object?> value => value,
  final value => throw formatFieldError(context, key, 'must be a Map', value),
};

/// Reads a list at [key], rejecting a missing or mistyped value.
List<Object?> readList(
  Map<String, Object?> map,
  String key, {
  required String context,
}) => switch (map[key]) {
  final List<Object?> value => value,
  final value => throw formatFieldError(context, key, 'must be a List', value),
};

/// Builds the shared `fromMap` failure message.
FormatException formatFieldError(
  String context,
  String field,
  String requirement,
  Object? value,
) => FormatException("$context.fromMap: '$field' $requirement, got $value");
