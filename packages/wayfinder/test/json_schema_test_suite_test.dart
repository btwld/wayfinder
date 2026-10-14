import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/published_schemas.dart';
import 'package:wayfinder/src/rules/schema.dart';

const expectedSkippedGroups = <String, Set<String>>{
  'type.json': {},
  'enum.json': {},
  'const.json': {},
  'pattern.json': {},
  'minLength.json': {},
  'maxLength.json': {},
  'required.json': {},
  'minProperties.json': {},
  'properties.json': {
    'properties, patternProperties, additionalProperties interaction',
  },
  'additionalProperties.json': {
    'additionalProperties being false does not allow other properties',
    'non-ASCII pattern with additionalProperties',
    'dependentSchemas with additionalProperties',
  },
  'propertyNames.json': {},
  'items.json': {
    'items and subitems',
    'prefixItems with no additional items allowed',
    'items does not look in applicators, valid case',
    'prefixItems validation adjusts the starting index for items',
    'items with heterogeneous array',
  },
  'uniqueItems.json': {
    'uniqueItems with an array of items',
    'uniqueItems with an array of items and additionalItems=false',
    'uniqueItems=false with an array of items',
    'uniqueItems=false with an array of items and additionalItems=false',
  },
  'minItems.json': {},
  'maxItems.json': {},
  'contains.json': {'contains keyword validation', 'items + contains'},
  'not.json': {
    "collect annotations inside a 'not', even if collection is disabled",
  },
  'allOf.json': {'allOf simple types', 'allOf combined with anyOf, oneOf'},
  'anyOf.json': {'anyOf'},
  'oneOf.json': {'oneOf'},
  'if-then-else.json': {
    'if and then without else',
    'if and else without then',
    'validate against correct branch, then vs else',
    'non-interference across combined schemas',
  },
  'ref.json': {
    'root pointer ref',
    'relative pointer ref to object',
    'relative pointer ref to array',
    'remote ref, containing refs itself',
    'Recursive references between schemas',
    'ref creates new scope when adjacent to keywords',
    'refs with relative uris and defs',
    'relative refs with absolute uris and defs',
    r'$id must be resolved against nearest parent, not just immediate parent',
    r'order of evaluation: $id and $ref',
    r'order of evaluation: $id and $anchor and $ref',
    r'order of evaluation: $id and $ref on nested schema',
    r'simple URN base URI with $ref via the URN',
    'URN base URI with URN and JSON pointer ref',
    'URN base URI with URN and anchor ref',
    'URN ref with nested pointer ref',
    'ref to if',
    'ref to then',
    'ref to else',
    'ref with absolute-path-reference',
    r'empty tokens in $ref json-pointer',
  },
  'boolean_schema.json': {},
  'defs.json': {'validate definition against metaschema'},
  'optional/format/date-time.json': {},
};

void main() {
  final suiteDir = p.join('test', 'json_schema_test_suite');

  group('JSON-Schema-Test-Suite draft2020-12', () {
    for (final MapEntry(key: file, value: expectedSkips)
        in expectedSkippedGroups.entries) {
      test(file, () {
        final groups =
            jsonDecode(File(p.join(suiteDir, file)).readAsStringSync())
                as List<Object?>;
        final skipped = <String>{};
        for (final group in groups.cast<Map<String, Object?>>()) {
          final description = group['description']! as String;
          final BoundSchema schema;
          try {
            schema = RuleSchema.parse(group['schema']).bind(const {});
          } on RuleSchemaException catch (error) {
            expect(error.unsupported, isTrue, reason: '$file: $description');
            skipped.add(description);
            continue;
          }
          final worded = PublishedSchema(
            jsonEncode(switch (group['schema']) {
              final bool always => {
                'allOf': [always],
              },
              final other => other,
            }),
          );
          final cases = (group['tests']! as List<Object?>)
              .cast<Map<String, Object?>>();
          for (final testCase in cases) {
            final name = '$file: $description / ${testCase['description']}';
            final valid = testCase['valid']! as bool;
            expect(schema.accepts(testCase['data']), valid, reason: name);
            expect(
              worded.violation(testCase['data']) == null,
              valid,
              reason: '$name worded',
            );
          }
        }
        expect(skipped, expectedSkips, reason: '$file skipped groups');
      });
    }
  });
}
