import 'dart:convert';

import 'package:ack/ack.dart';

import 'generated/published_schemas.g.dart';

final _configuration = _PublishedSchema(wayfinderConfigurationSchema);
final _package = _PublishedSchema(wayfinderProfileSchema);

String? configurationSchemaViolation(Object? configuration) {
  final violation = _configuration.violation(configuration);
  if (violation == null) return null;
  final at = violation.at;
  final where = at.isEmpty
      ? 'the root'
      : at.map((s) => '/${_escape(s)}').join();
  return 'is invalid at $where: ${violation.reason}';
}

/// Why [package], a decoded `wayfinder-profile.json`, does not match
/// `docs/schemas/wayfinder-profile.schema.json`, or null when it does.
({String where, String reason})? profilePackageSchemaViolation(
  Object? package,
) {
  final violation = _package.violation(package);
  if (violation == null) return null;
  return (
    where: _packagePath([...violation.at, ?violation.property]),
    reason: violation.reason,
  );
}

typedef _Violation = ({List<String> at, String? property, String reason});

/// One embedded published schema: its decoded document, which supplies the
/// expected values and descriptions Ack's errors locate but do not carry,
/// and the Ack schema imported from it once.
final class _PublishedSchema {
  _PublishedSchema(String source)
    : _document = jsonDecode(source) as Map<String, Object?>;

  final Map<String, Object?> _document;
  late final _schema = Ack.fromJsonSchema(_document);

  _Violation? violation(Object? value) {
    final result = _schema.safeParse(value);
    if (result.isOk) return null;
    return switch (result.getError()) {
      final JsonSchemaValidationError error => _keywordViolation(error),
      // Ack checks a root null before any keyword.
      SchemaConstraintsError() => (
        at: const [],
        property: null,
        reason: 'must not be null',
      ),
      // jsonDecode yields JSON except for numbers too large for a double.
      SchemaValidationError() => (
        at: const [],
        property: null,
        reason: 'must contain only finite numbers',
      ),
      final error => (at: const [], property: null, reason: error.message),
    };
  }

  _Violation _keywordViolation(JsonSchemaValidationError error) {
    final pointer = _tokens(Uri.decodeComponent(error.pointer.substring(1)));
    final path = _tokens(error.path.substring(1));
    final owner = path.isEmpty
        ? const <String>[]
        : path.sublist(0, path.length - 1);
    // TODO(https://github.com/btwld/ack/issues/203): classify propertyNames
    // and additionalProperties failures on the error's keywordLocation, not
    // its pointer, which stops at a $ref target shared with member values.
    if (_keywordTokens(pointer).contains('propertyNames')) {
      return (
        at: owner,
        property: path.last,
        reason: 'has invalid property name ${jsonEncode(path.last)}',
      );
    }
    return switch (error.keyword) {
      'required' => (
        at: owner,
        property: path.last,
        reason: 'is missing required property ${path.last}',
      ),
      '' when pointer.lastOrNull == 'additionalProperties' => (
        at: owner,
        property: path.last,
        reason: 'has unknown property ${path.last}',
      ),
      final keyword => (
        at: path,
        property: null,
        reason: _reason(
          keyword,
          _at(pointer),
          _at(pointer.sublist(0, pointer.length - 1)),
        ),
      ),
    };
  }

  Object? _at(List<String> pointer) {
    Object? node = _document;
    for (final token in pointer) {
      node = switch (node) {
        final Map<String, Object?> map => map[token],
        final List<Object?> list => list.elementAtOrNull(
          int.tryParse(token) ?? -1,
        ),
        _ => null,
      };
    }
    return node;
  }

  static const _keywordsFollowedByNameOrIndex = {
    'properties',
    r'$defs',
    'allOf',
    'anyOf',
    'oneOf',
  };

  static Iterable<String> _keywordTokens(List<String> pointer) sync* {
    var skipNext = false;
    for (final token in pointer) {
      if (skipNext) {
        skipNext = false;
        continue;
      }
      yield token;
      skipNext = _keywordsFollowedByNameOrIndex.contains(token);
    }
  }
}

String _reason(String keyword, Object? keywordValue, Object? parentSchema) =>
    switch ((keyword, keywordValue)) {
      ('type', final String type) => 'must be ${_typeNoun(type)}',
      ('type', final List<Object?> types) =>
        'must be ${types.cast<String>().map(_typeNoun).join(' or ')}',
      ('const', _) => 'must be ${jsonEncode(keywordValue)}',
      ('enum', final List<Object?> values) =>
        'must be one of ${values.map(_literal).join(', ')}',
      ('minLength', 1) => 'must be a non-empty string',
      ('minLength', _) => 'must have at least $keywordValue characters',
      ('maxLength', _) => 'must have at most $keywordValue characters',
      ('minProperties', 1) => 'must not be empty',
      ('minProperties', _) => 'must have at least $keywordValue properties',
      ('minItems', 1) => 'must not be empty',
      ('minItems', _) => 'must have at least $keywordValue items',
      ('pattern', _) => switch (parentSchema) {
        {'description': final String text} => 'must be $text',
        _ => 'must match pattern $keywordValue',
      },
      ('oneOf', _) => 'must match exactly one of its allowed shapes',
      _ => 'fails ${keyword.isEmpty ? 'false' : keyword}',
    };

/// JSON Pointer tokens, unescaped. Ack's error path is a `#`-prefixed RFC
/// 6901 pointer; its schema pointer is the same after percent-decoding.
List<String> _tokens(String pointer) => [
  for (final token in pointer.split('/').skip(1))
    token.replaceAll('~1', '/').replaceAll('~0', '~'),
];

String _escape(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');

String _packagePath(List<String> segments) {
  if (segments.isEmpty) return 'package';
  final where = StringBuffer();
  for (final segment in segments) {
    if (int.tryParse(segment) != null) {
      where.write('[$segment]');
    } else {
      where.write(where.isEmpty ? segment : '.$segment');
    }
  }
  return '$where';
}

String _typeNoun(String type) => switch (type) {
  'null' => 'null',
  'object' || 'array' || 'integer' => 'an $type',
  _ => 'a $type',
};

String _literal(Object? value) => value is String ? value : jsonEncode(value);
