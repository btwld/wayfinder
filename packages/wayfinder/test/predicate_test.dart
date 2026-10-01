import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/rules/predicate.dart';

/// Groups whose schema uses a keyword outside the predicate's subset must
/// fail to compile. Pinning the count per file turns a silently widened or
/// narrowed subset into a failure instead of a quieter test run.
const expectedSkippedGroups = <String, int>{
  'type.json': 0,
  'enum.json': 1,
  'const.json': 0,
  'pattern.json': 0,
  'minLength.json': 0,
  'maxLength.json': 0,
  'required.json': 0,
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

/// Cases inside a compiled group whose outcome deliberately differs from the
/// suite. Each entry asserts the divergence, so a fixed one shows up here.
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
          final JsonPredicate predicate;
          try {
            predicate = JsonPredicate.compile(group['schema']);
          } on JsonPredicateException {
            skipped++;
            continue;
          }
          final cases = (group['tests']! as List<Object?>)
              .cast<Map<String, Object?>>();
          for (final testCase in cases) {
            final name = '${group['description']} / ${testCase['description']}';
            final expected = testCase['valid']! as bool;
            final actual = predicate.test(testCase['data']);
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

  group('x-slot', () {
    test('an empty slot compiles to false', () {
      final predicate = JsonPredicate.compile(
        {'x-slot': 'kinds'},
        slots: {'kinds': []},
      );
      expect(predicate.test('x'), isFalse);
      expect(predicate.test(null), isFalse);
    });

    test('a filled slot accepts members only', () {
      final predicate = JsonPredicate.compile(
        {
          'properties': {
            'kind': {r'$ref': r'#/$defs/kind'},
          },
        },
        defs: {
          'kind': {'x-slot': 'kinds'},
        },
        slots: {
          'kinds': ['concept', 'decision'],
        },
      );
      expect(predicate.test({'kind': 'concept'}), isTrue);
      expect(predicate.test({'kind': 'decision'}), isTrue);
      expect(predicate.test({'kind': 'other'}), isFalse);
      expect(predicate.test({'kind': 1}), isFalse);
    });

    test('an unknown slot is a compile error', () {
      expect(
        () => JsonPredicate.compile({'x-slot': 'missing'}),
        throwsA(
          isA<JsonPredicateException>().having(
            (e) => e.pointer,
            'pointer',
            '/x-slot',
          ),
        ),
      );
    });
  });

  group('compile errors', () {
    test('an empty enum is rejected', () {
      expect(
        () => JsonPredicate.compile({'enum': <Object?>[]}),
        throwsA(
          isA<JsonPredicateException>().having(
            (e) => e.pointer,
            'pointer',
            '/enum',
          ),
        ),
      );
    });

    test('an unknown keyword names its pointer', () {
      expect(
        () => JsonPredicate.compile({
          'properties': {
            'tags': {'patternProperties': <String, Object?>{}},
          },
        }),
        throwsA(
          isA<JsonPredicateException>().having(
            (e) => e.pointer,
            'pointer',
            '/properties/tags/patternProperties',
          ),
        ),
      );
    });

    test('a format other than date-time is rejected', () {
      expect(
        () => JsonPredicate.compile({'format': 'email'}),
        throwsA(
          isA<JsonPredicateException>().having(
            (e) => e.pointer,
            'pointer',
            '/format',
          ),
        ),
      );
    });

    test('a ref cycle with no instance descent is rejected', () {
      expect(
        () => JsonPredicate.compile({
          r'$ref': r'#/$defs/a',
          r'$defs': {
            'a': {
              'anyOf': [
                {r'$ref': r'#/$defs/b'},
              ],
            },
            'b': {r'$ref': r'#/$defs/a'},
          },
        }),
        throwsA(
          isA<JsonPredicateException>().having(
            (e) => e.pointer,
            'pointer',
            anyOf(r'/$defs/a/anyOf/0/$ref', r'/$defs/b/$ref'),
          ),
        ),
      );
    });
  });

  test('a ref cycle through the instance compiles and terminates', () {
    final predicate = JsonPredicate.compile({
      r'$ref': r'#/$defs/node',
      r'$defs': {
        'node': {
          'type': 'object',
          'required': ['name'],
          'properties': {
            'name': {'type': 'string'},
            'children': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/node'},
            },
          },
        },
      },
    });
    final tree = {
      'name': 'root',
      'children': [
        {'name': 'leaf', 'children': <Object?>[]},
      ],
    };
    expect(predicate.test(tree), isTrue);
    expect(
      predicate.test({
        'name': 'root',
        'children': [
          {'children': <Object?>[]},
        ],
      }),
      isFalse,
    );
  });
}
