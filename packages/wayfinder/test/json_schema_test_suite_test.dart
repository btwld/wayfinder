import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/rules/schema.dart';

const expectedSkippedGroups = <String, int>{
  'type.json': 0,
  'enum.json': 0,
  'const.json': 0,
  'pattern.json': 0,
  'minLength.json': 0,
  'maxLength.json': 0,
  'required.json': 0,
  'minProperties.json': 0,
  'properties.json': 1,
  'additionalProperties.json': 3,
  'propertyNames.json': 0,
  'items.json': 5,
  'uniqueItems.json': 4,
  'minItems.json': 0,
  'maxItems.json': 0,
  'contains.json': 2,
  'not.json': 1,
  'allOf.json': 2,
  'anyOf.json': 1,
  'oneOf.json': 1,
  'if-then-else.json': 4,
  'ref.json': 21,
  'boolean_schema.json': 0,
  'defs.json': 1,
  'optional/format/date-time.json': 0,
};

const acceptedDivergences = <String, String>{};

void main() {
  final suiteDir = p.join('test', 'json_schema_test_suite');

  group('JSON-Schema-Test-Suite draft2020-12', () {
    final seenDivergences = <String>{};
    for (final MapEntry(key: file, value: expectedSkips)
        in expectedSkippedGroups.entries) {
      test(file, () {
        final groups =
            jsonDecode(File(p.join(suiteDir, file)).readAsStringSync())
                as List<Object?>;
        var skipped = 0;
        for (final group in groups.cast<Map<String, Object?>>()) {
          final BoundSchema schema;
          try {
            schema = RuleSchema.parse(group['schema']).bind(const {});
          } on RuleSchemaException {
            skipped++;
            continue;
          }
          final cases = (group['tests']! as List<Object?>)
              .cast<Map<String, Object?>>();
          for (final testCase in cases) {
            final name = '${group['description']} / ${testCase['description']}';
            final expected = testCase['valid']! as bool;
            final actual = schema.accepts(testCase['data']);
            if (acceptedDivergences.containsKey(name)) {
              seenDivergences.add(name);
              expect(actual, isNot(expected), reason: '$file: $name');
            } else {
              expect(actual, expected, reason: '$file: $name');
            }
          }
        }
        expect(skipped, expectedSkips, reason: '$file skipped groups');
      });
    }

    test('every accepted divergence is still exercised', () {
      expect(seenDivergences, acceptedDivergences.keys.toSet());
    });
  });
}
