import 'package:test/test.dart';
import 'package:wayfinder/src/rules/profile.dart';
import 'package:wayfinder/src/rules/schema.dart';

Matcher refusedAt(String pointer, {Object? message, bool? unsupported}) =>
    throwsA(
      isA<RuleSchemaException>()
          .having((e) => e.pointer, 'pointer', pointer)
          .having((e) => e.message, 'message', message ?? anything)
          .having((e) => e.unsupported, 'unsupported', unsupported ?? anything),
    );

final _smoke = <String, ({Object? schema, Object? pass, Object? fail})>{
  'type': (schema: {'type': 'string'}, pass: 'a', fail: 1),
  'enum': (
    schema: {
      'enum': ['a'],
    },
    pass: 'a',
    fail: 'b',
  ),
  'const': (
    schema: {
      'const': {'a': 1},
    },
    pass: {'a': 1.0},
    fail: {'a': 2},
  ),
  'pattern': (schema: {'pattern': r'^\p{Lu}'}, pass: 'Éa', fail: 'éa'),
  'minLength': (schema: {'minLength': 2}, pass: '😀😀', fail: '😀'),
  'maxLength': (schema: {'maxLength': 1}, pass: '😀', fail: 'ab'),
  'format': (
    schema: {'format': 'date-time'},
    pass: '1990-12-31T23:59:60Z',
    fail: '1990-02-31T00:00:00Z',
  ),
  'required': (
    schema: {
      'required': ['a'],
    },
    pass: {'a': null},
    fail: <String, Object?>{},
  ),
  'minProperties': (
    schema: {'minProperties': 1},
    pass: {'a': 1},
    fail: <String, Object?>{},
  ),
  'properties': (
    schema: {
      'properties': {
        'a': {'type': 'string'},
      },
    },
    pass: {'b': 1},
    fail: {'a': 1},
  ),
  'additionalProperties': (
    // The upstream group Ack's CI does not run: additionalProperties with propertyNames.
    schema: {
      'propertyNames': {'maxLength': 5},
      'additionalProperties': {'type': 'number'},
    },
    pass: {'apple': 4},
    fail: {'fig': 2, 'pear': 'available'},
  ),
  'propertyNames': (
    schema: {
      'propertyNames': {'pattern': '^a'},
    },
    pass: {'ab': 1},
    fail: {'b': 1},
  ),
  'items': (
    schema: {
      'items': {'type': 'integer'},
    },
    pass: [1, 2.0],
    fail: [1, 'a'],
  ),
  'uniqueItems': (
    schema: {'uniqueItems': true},
    pass: [1, '1'],
    fail: [1, 1.0],
  ),
  'minItems': (schema: {'minItems': 1}, pass: [1], fail: <Object?>[]),
  'maxItems': (schema: {'maxItems': 1}, pass: [1], fail: [1, 2]),
  'contains': (
    schema: {
      'contains': {'const': 1},
    },
    pass: [0, 1],
    fail: [0],
  ),
  'not': (
    schema: {
      'not': {'type': 'string'},
    },
    pass: 1,
    fail: 'a',
  ),
  'allOf': (
    schema: {
      'allOf': [
        {'minLength': 1},
        {'maxLength': 1},
      ],
    },
    pass: 'a',
    fail: 'ab',
  ),
  'anyOf': (
    schema: {
      'anyOf': [
        {'type': 'string'},
        {'type': 'null'},
      ],
    },
    pass: null,
    fail: 1,
  ),
  'oneOf': (
    schema: {
      'oneOf': [
        {'type': 'number'},
        {'type': 'integer'},
      ],
    },
    pass: 1.5,
    fail: 1,
  ),
  'if': (
    schema: {
      'if': {'type': 'string'},
      'then': {'minLength': 1},
    },
    pass: 1,
    fail: '',
  ),
  'then': (
    schema: {
      'if': {'type': 'string'},
      'then': {'minLength': 1},
    },
    pass: 'a',
    fail: '',
  ),
  'else': (
    schema: {
      'if': {'type': 'string'},
      'else': {'type': 'null'},
    },
    pass: null,
    fail: 1,
  ),
  r'$ref': (
    schema: {
      r'$ref': r'#/$defs/a',
      r'$defs': {
        'a': {'type': 'string'},
      },
    },
    pass: 'a',
    fail: 1,
  ),
};

void main() {
  group('the subset', () {
    test('every admitted assertion or applicator has a smoke case', () {
      const annotations = {
        r'$schema',
        r'$comment',
        'title',
        'description',
        'examples',
        'default',
        'deprecated',
        r'$id',
        r'$defs',
      };
      expect(
        _smoke.keys.toSet(),
        subsetKeywords.toSet().difference(annotations),
      );
    });

    for (final MapEntry(key: keyword, value: (:schema, :pass, :fail))
        in _smoke.entries) {
      test('$keyword is evaluated', () {
        final bound = RuleSchema.parse(schema).bind(const {});
        expect(bound.accepts(pass), isTrue, reason: 'pass');
        expect(bound.accepts(fail), isFalse, reason: 'fail');
      });
    }

    test('anything else, including any x- key, is unsupported', () {
      for (final keyword in [
        'patternProperties',
        'maxProperties',
        r'$anchor',
        'x-slot',
      ]) {
        expect(
          () => RuleSchema.parse({
            'properties': {
              'a': {keyword: 1},
            },
          }),
          refusedAt(
            '/properties/a/$keyword',
            message: 'unsupported keyword "$keyword"',
            unsupported: true,
          ),
        );
      }
    });

    test('only a ref to a root def is followed', () {
      for (final ref in [
        '#',
        '#a',
        '#/properties/a',
        r'#/$defs/a/properties/b',
        r'other.json#/$defs/a',
        r'#/$defs/a%2Fnot',
        r'#/$defs/a%2fnot',
      ]) {
        expect(
          () => RuleSchema.parse({
            r'$ref': ref,
            r'$defs': {
              'a': {'not': true},
              'a/not': true,
            },
          }),
          refusedAt(r'/$ref', unsupported: true),
          reason: ref,
        );
      }
      final escaped = RuleSchema.parse(
        {r'$ref': r'#/$defs/a~1b'},
        defs: {
          'a/b': {
            'required': ['z'],
          },
        },
      );
      expect(escaped.rootPropertyNames, {'z'});
      expect(escaped.bind(const {}).accepts(<String, Object?>{}), isFalse);
      expect(escaped.bind(const {}).accepts({'z': 1}), isTrue);
      expect(
        () => RuleSchema.parse({
          'properties': {
            'a': {r'$id': 'a.json'},
          },
        }),
        refusedAt(r'/properties/a/$id', unsupported: true),
      );
    });

    test('a ref with a malformed percent escape is invalid', () {
      expect(
        () => RuleSchema.parse({r'$ref': r'#/$defs/%zz'}, defs: {'x': true}),
        refusedAt(
          r'/$ref',
          message: 'has a malformed percent escape',
          unsupported: false,
        ),
      );
    });

    test('Ack refuses a meta-schema-invalid form as malformed', () {
      expect(
        () => RuleSchema.parse({
          'required': ['a', 'a'],
        }),
        refusedAt('/required', unsupported: false),
      );
      expect(
        () => RuleSchema.parse({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
        }),
        refusedAt(r'/$schema', unsupported: true),
      );
      expect(
        () => RuleSchema.parse({
          r'$ref': r'#/$defs/a',
          r'$defs': {
            'a': {
              'anyOf': [
                {r'$ref': r'#/$defs/a'},
              ],
            },
          },
        }),
        throwsA(
          isA<RuleSchemaException>().having(
            (e) => e.unsupported,
            'unsupported',
            isFalse,
          ),
        ),
      );
    });

    test('a malformed def is refused whether or not a rule reaches it', () {
      for (final (def, pointer) in [
        ({'minLength': -1}, r'/$defs/bad/minLength'),
        ({'pattern': '('}, r'/$defs/bad/pattern'),
        ({'type': 'strnig'}, r'/$defs/bad/type'),
        (
          {
            'required': ['a', 'a'],
          },
          r'/$defs/bad/required',
        ),
        ({'description': 1}, r'/$defs/bad/description'),
        ({r'$ref': r'#/$defs/bad'}, r'/$defs/bad/$ref'),
      ]) {
        for (final (reach, schema) in [
          ('reached', {r'$ref': r'#/$defs/bad'}),
          ('unreached', {'type': 'object'}),
        ]) {
          expect(
            () => RuleSchema.parse(schema, defs: {'bad': def}),
            refusedAt(pointer, unsupported: false),
            reason: '$reach $def',
          );
          expect(
            () => RuleSchema.parse({
              ...schema,
              r'$defs': {'bad': def},
            }),
            refusedAt(pointer, unsupported: false),
            reason: 'rule-local $reach $def',
          );
        }
      }
      expect(
        () => RuleSchema.parse(true, defs: {'a/b~c%2Fd#e f': true}),
        returnsNormally,
      );
    });

    test('an empty enum matches nothing, as 2020-12 allows', () {
      expect(
        RuleSchema.parse({'enum': <Object?>[]}).bind(const {}).accepts('a'),
        isFalse,
      );
    });
  });

  group('slots', () {
    test('bind fills a slot; a slot it omits matches nothing', () {
      final schema = RuleSchema.parse(
        {
          'properties': {
            'kind': {r'$ref': r'#/$defs/kind'},
          },
        },
        defs: {
          'kind': {r'$ref': r'#/$defs/profile.types'},
        },
      );
      expect(schema.slots, {Slot.profileTypes});
      final bound = schema.bind({
        Slot.profileTypes: ['concept'],
      });
      expect(bound.accepts({'kind': 'concept'}), isTrue);
      expect(bound.accepts({'kind': 'other'}), isFalse);
      expect(schema.bind(const {}).accepts({'kind': 'concept'}), isFalse);
    });

    test('a rule that reaches no slot compiles once', () {
      final schema = RuleSchema.parse({'type': 'string'});
      expect(
        identical(
          schema.bind(const {}),
          schema.bind({
            Slot.profileTypes: ['a'],
          }),
        ),
        isTrue,
      );
    });

    test('an unknown slot or def is not a ref target', () {
      expect(
        () => RuleSchema.parse({r'$ref': r'#/$defs/profile.names'}),
        refusedAt(
          r'/$ref',
          message: r'$ref target is not in $defs',
          unsupported: false,
        ),
      );
    });

    test('a def named after a slot is reserved', () {
      expect(
        () => RuleSchema.parse(true, defs: {'profile.types': true}),
        refusedAt(r'/$defs/profile.types', message: contains('reserved')),
      );
    });
  });

  group('analysis', () {
    test(
      'names come from the same instance only, through refs and in-place applicators',
      () {
        final schema = RuleSchema.parse(
          {
            'allOf': [
              {r'$ref': r'#/$defs/same'},
            ],
            'not': {
              'required': ['negated'],
            },
            'properties': {
              'child': {r'$ref': r'#/$defs/below'},
            },
          },
          defs: {
            'same': {
              'required': ['viaRef'],
            },
            'below': {
              'required': ['nested'],
            },
          },
        );
        expect(schema.rootPropertyNames, {'viaRef', 'negated', 'child'});
        expect(schema.mayObserveUnnamedRootProperties, isFalse);
      },
    );

    test('a keyword that reads every property is seen through a ref', () {
      final schema = RuleSchema.parse(
        {r'$ref': r'#/$defs/closed'},
        defs: {
          'closed': {'additionalProperties': false},
        },
      );
      expect(schema.mayObserveUnnamedRootProperties, isTrue);
    });
  });
}
