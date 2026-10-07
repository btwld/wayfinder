import 'dart:convert';

import 'generated/published_schemas.g.dart';
import 'rules/predicate.dart';

final _configuration = JsonPredicate.compile(
  jsonDecode(wayfinderConfigurationSchema),
);
final _package = JsonPredicate.compile(jsonDecode(wayfinderProfileSchema));

String? configurationSchemaViolation(Object? configuration) {
  final failure = _configuration.firstFailure(configuration);
  if (failure == null) return null;
  final where = failure.pointer.isEmpty ? 'the root' : failure.pointer;
  return 'is invalid at $where: ${schemaFailureReason(failure)}';
}

/// Why [package], a decoded `wayfinder-profile.json`, does not match
/// `docs/schemas/wayfinder-profile.schema.json`, or null when it does.
JsonPredicateFailure? profilePackageSchemaFailure(Object? package) =>
    _package.firstFailure(package);

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
