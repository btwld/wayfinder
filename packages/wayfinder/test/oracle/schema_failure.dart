// The messages Ack's renderer replaces: schemaFailureReason from
// lib/src/published_schemas.dart and schemaFailureWhere from
// lib/src/profile_package.dart, verbatim as of 8735c53, so ack_parity_test
// compares wording against them. Deleted with json_predicate.dart.

import 'dart:convert';

import 'json_predicate.dart';

String schemaFailureReason(JsonPredicateFailure failure) => switch (failure) {
  JsonPredicateFailure(keyword: 'type', expected: final List<String> types) =>
    'must be ${types.map(_typeNoun).join(' or ')}',
  JsonPredicateFailure(keyword: 'const', :final expected) =>
    'must be ${jsonEncode(expected)}',
  JsonPredicateFailure(keyword: 'enum', expected: final List<Object?> values) =>
    'must be one of ${values.map(_literal).join(', ')}',
  JsonPredicateFailure(keyword: 'minLength', expected: 1) =>
    'must be a non-empty string',
  JsonPredicateFailure(keyword: 'minLength', :final expected) =>
    'must have at least $expected characters',
  JsonPredicateFailure(keyword: 'maxLength', :final expected) =>
    'must have at most $expected characters',
  JsonPredicateFailure(keyword: 'minProperties', expected: 1) =>
    'must not be empty',
  JsonPredicateFailure(keyword: 'minProperties', :final expected) =>
    'must have at least $expected properties',
  JsonPredicateFailure(keyword: 'minItems', expected: 1) => 'must not be empty',
  JsonPredicateFailure(keyword: 'minItems', :final expected) =>
    'must have at least $expected items',
  JsonPredicateFailure(keyword: 'pattern', description: final String text) =>
    'must be $text',
  JsonPredicateFailure(keyword: 'pattern', :final expected) =>
    'must match pattern $expected',
  JsonPredicateFailure(keyword: 'required', :final property) =>
    'is missing required property $property',
  JsonPredicateFailure(keyword: 'additionalProperties', :final property) =>
    'has unknown property $property',
  JsonPredicateFailure(keyword: 'propertyNames', :final property) =>
    'has invalid property name ${jsonEncode(property)}',
  JsonPredicateFailure(keyword: 'oneOf') =>
    'must match exactly one of its allowed shapes',
  JsonPredicateFailure(:final keyword) => 'fails $keyword',
};

String _typeNoun(String type) => switch (type) {
  'null' => 'null',
  'object' || 'array' || 'integer' => 'an $type',
  _ => 'a $type',
};

String _literal(Object? value) => value is String ? value : jsonEncode(value);

/// [failure]'s pointer as a path into the document, such as
/// `rules[3].check.subject`, or [root] for the document itself.
String schemaFailureWhere(
  JsonPredicateFailure failure, {
  required String root,
}) {
  final segments = [
    for (final segment in failure.pointer.split('/').skip(1))
      segment.replaceAll('~1', '/').replaceAll('~0', '~'),
    ?failure.property,
  ];
  if (segments.isEmpty) return root;
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
