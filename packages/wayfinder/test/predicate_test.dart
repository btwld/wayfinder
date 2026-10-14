import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/rules/predicate.dart';

const expectedSkippedGroups = <String, int>{
  'type.json': 0,
  'enum.json': 1,
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
            expect(
              predicate.firstFailure(testCase['data']) == null,
              actual,
              reason: '$file: $name firstFailure agrees with test',
            );
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

  group('firstFailure', () {
    final predicate = JsonPredicate.compile({
      'type': 'object',
      'required': ['name', 'items'],
      'additionalProperties': false,
      'properties': {
        'name': {'type': 'string', 'minLength': 1, 'pattern': r'^[a-z]+$'},
        'items': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/item'},
        },
        'labels': {
          'propertyNames': {'pattern': r'^[a-z]+$'},
        },
      },
      r'$defs': {
        'item': {
          'properties': {
            'side': {
              'enum': ['left', 'right'],
            },
          },
        },
      },
    });

    JsonPredicateFailure? failure(Object? instance) =>
        predicate.firstFailure(instance);

    test('is null for a conforming instance', () {
      expect(failure({'name': 'a', 'items': <Object?>[]}), isNull);
    });

    test('names the missing member on its object', () {
      expect(
        failure({'name': 'a'}),
        isA<JsonPredicateFailure>()
            .having((f) => f.pointer, 'pointer', '')
            .having((f) => f.keyword, 'keyword', 'required')
            .having((f) => f.property, 'property', 'items'),
      );
    });

    test('names an unknown member on its object', () {
      expect(
        failure({'name': 'a', 'items': <Object?>[], 'x/y': 1}),
        isA<JsonPredicateFailure>()
            .having((f) => f.pointer, 'pointer', '')
            .having((f) => f.keyword, 'keyword', 'additionalProperties')
            .having((f) => f.property, 'property', 'x/y'),
      );
    });

    test('reports keywords in schema document order', () {
      expect(
        failure({'name': '', 'items': <Object?>[]}),
        isA<JsonPredicateFailure>()
            .having((f) => f.pointer, 'pointer', '/name')
            .having((f) => f.keyword, 'keyword', 'minLength')
            .having((f) => f.expected, 'expected', 1),
      );
      expect(failure({'name': 'A', 'items': <Object?>[]})?.keyword, 'pattern');
      expect(failure(<Object?>[])?.keyword, 'type');
    });

    test('points through items and refs to the failing value', () {
      expect(
        failure({
          'name': 'a',
          'items': [
            {'side': 'left'},
            {'side': 'up'},
          ],
        }),
        isA<JsonPredicateFailure>()
            .having((f) => f.pointer, 'pointer', '/items/1/side')
            .having((f) => f.keyword, 'keyword', 'enum')
            .having((f) => f.expected, 'expected', ['left', 'right']),
      );
    });

    test('carries the description nearest a failing pattern', () {
      final described = JsonPredicate.compile({
        'properties': {
          'own': {'pattern': '^a', 'description': 'own words'},
          'viaDef': {r'$ref': r'#/$defs/lower', 'description': 'not this'},
          'bare': {'pattern': '^a'},
        },
        r'$defs': {
          'lower': {
            'description': 'def words',
            'allOf': [
              {'pattern': '^a'},
            ],
          },
        },
      });
      String? description(Map<String, Object?> instance) =>
          described.firstFailure(instance)?.description;
      expect(description({'own': 'b'}), 'own words');
      expect(description({'viaDef': 'b'}), 'def words');
      expect(description({'bare': 'b'}), isNull);
    });

    test('names the property a propertyNames check rejects', () {
      expect(
        failure({
          'name': 'a',
          'items': <Object?>[],
          'labels': {'ok': 1, 'Bad': 2},
        }),
        isA<JsonPredicateFailure>()
            .having((f) => f.pointer, 'pointer', '/labels')
            .having((f) => f.keyword, 'keyword', 'propertyNames')
            .having((f) => f.property, 'property', 'Bad'),
      );
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
