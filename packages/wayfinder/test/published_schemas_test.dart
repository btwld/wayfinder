import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder/src/generated/published_schemas.g.dart';
import 'package:wayfinder/src/published_schemas.dart';
import 'package:wayfinder/src/rules/schema.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

String configMessage(String json) {
  try {
    WayfinderProjectConfig.parse(json);
  } on WayfinderConfigException catch (error) {
    return error.message;
  }
  fail('parsed');
}

void main() {
  final schemas = {
    'wayfinder.schema.json': jsonDecode(wayfinderConfigurationSchema),
    'wayfinder-profile.schema.json': jsonDecode(wayfinderProfileSchema),
  };

  for (final MapEntry(key: name, value: schema) in schemas.entries) {
    test('$name is written inside the Profile keyword subset', () {
      expect(() => RuleSchema.parse(schema), returnsNormally);
    });
  }

  test('a pattern failure carries the description nearest it', () {
    final described = PublishedSchema(
      jsonEncode({
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
      }),
    );
    String? reason(Map<String, Object?> instance) =>
        described.violation(instance)?.reason;
    expect(reason({'own': 'b'}), 'must be own words');
    expect(reason({'viaDef': 'b'}), 'must be def words');
    expect(reason({'bare': 'b'}), 'must match pattern ^a');
  });

  group('accepted wording changes', () {
    test('a root null is reported as null', () {
      expect(
        configMessage('null'),
        'wayfinder.json is invalid at the root: must not be null.',
      );
      expect(
        () => ProfilePackage.parse('null'),
        throwsA(
          isA<ProfilePackageException>()
              .having((error) => error.where, 'where', 'package')
              .having((error) => error.message, 'message', 'must not be null'),
        ),
      );
    });

    test('the first failure follows Ack keyword order, not document order', () {
      expect(
        configMessage('{"surprise": true}'),
        'wayfinder.json is invalid at the root: is missing required property '
        'version.',
      );
    });

    test('a number too large for a double is not JSON', () {
      expect(
        configMessage('{"version": 1e999, "profiles": {}}'),
        'wayfinder.json is invalid at the root: must contain only finite '
        'numbers.',
      );
    });
  });

  test('a member name and a member value failing one def are told apart', () {
    const profile =
        '"source": {"git": "g", "ref": "r", "path": "p"}, '
        '"applies_to": ["docs"]';
    expect(
      configMessage(
        '{"version": 1, "profiles": {"a": {$profile, '
        '"actors": {" ": {"name": "n"}}}}}',
      ),
      'wayfinder.json is invalid at /profiles/a/actors: has invalid '
      'property name " ".',
    );
    expect(
      configMessage(
        '{"version": 1, "profiles": {"a": {$profile, '
        '"actors": {"x": {"name": " "}}}}}',
      ),
      'wayfinder.json is invalid at /profiles/a/actors/x/name: must be a '
      'non-empty string.',
    );
  });

  group('an empty member key', () {
    const profile =
        '{"source": {"git": "g", "ref": "r", "path": "p"}, '
        '"applies_to": ["docs"]}';

    test('is named at the configuration root', () {
      expect(
        configMessage('{"version": 1, "profiles": {"a": $profile}, "": 1}'),
        'wayfinder.json is invalid at the root: has unknown property .',
      );
    });

    test('is named under profiles and actors', () {
      expect(
        configMessage('{"version": 1, "profiles": {"": $profile}}'),
        'wayfinder.json is invalid at /profiles: has invalid property name "".',
      );
      expect(
        configMessage(
          '{"version": 1, "profiles": {"a": {"source": {"git": "g", '
          '"ref": "r", "path": "p"}, "applies_to": ["docs"], '
          '"actors": {"": {"name": "n"}}}}}',
        ),
        'wayfinder.json is invalid at /profiles/a/actors: has invalid '
        'property name "".',
      );
    });

    test('is named in a package rule', () {
      final rule = {
        ...ruleJson(
          'a',
          subject: 'root',
          schema: true,
          valid: [<String, Object?>{}],
          invalid: [<String, Object?>{}],
        ),
        '': 1,
      };
      expect(
        () => ProfilePackage.parse(packageJson(rules: [rule])),
        throwsA(
          isA<ProfilePackageException>()
              .having((error) => error.where, 'where', 'rules[0].')
              .having(
                (error) => error.message,
                'message',
                'has unknown property ',
              ),
        ),
      );
    });
  });
}
