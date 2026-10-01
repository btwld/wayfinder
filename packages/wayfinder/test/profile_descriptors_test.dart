import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/generated/installed_profiles.g.dart';
import 'package:wayfinder/src/profile_release.dart';
import 'package:wayfinder/src/profile_rule_descriptors.dart';
import 'package:wayfinder/src/rules/catalog.dart';

void main() {
  final catalogs = {
    for (final release in [legacyProfileRelease, externalProfileRelease])
      release: RuleCatalog.installed(builtinProfileId, release),
  };

  test('the embedded catalog schema is the published one', () async {
    expect(
      wayfinderRulesSchema,
      await File(
        '../../docs/schemas/wayfinder-rules.schema.json',
      ).readAsString(),
    );
  });

  group('load checks the catalog schema first', () {
    Map<String, Object?> catalog({
      String release = '2026.1',
      Map<String, Object?> rule = const {},
    }) => {
      'format': 1,
      'namespace': 'x',
      'profile': {'id': 'x', 'release': release},
      'rules': [
        {
          'id': 'a',
          'category': 'structure',
          'severity': 'error',
          'status': 'stable',
          'ref': '§1',
          'description': 'd',
          'message': 'm',
          'check': {'builtin': 'link-graph-unavailable'},
          ...rule,
        },
      ],
    };

    Matcher rejectedAt(String where, String message) => throwsA(
      isA<RuleCatalogException>()
          .having((error) => error.where, 'where', where)
          .having((error) => error.message, 'message', contains(message)),
    );

    test('a release that is not year.serial', () {
      expect(
        () => RuleCatalog.parse(jsonEncode(catalog(release: 'probe'))),
        rejectedAt('profile.release', 'must match pattern'),
      );
      expect(RuleCatalog.parse(jsonEncode(catalog())).release, '2026.1');
    });

    test('an unknown severity, at the rule that carries it', () {
      expect(
        () => RuleCatalog.parse(jsonEncode(catalog(rule: {'severity': 'x'}))),
        rejectedAt('rules[0].severity', 'must be one of error, advisory'),
      );
    });

    test('an unknown key, named on its object', () {
      expect(
        () => RuleCatalog.parse(jsonEncode(catalog(rule: {'extra': 1}))),
        rejectedAt('rules[0].extra', 'unknown property'),
      );
    });

    test('the okf namespace', () {
      expect(
        () => RuleCatalog.parse(jsonEncode({...catalog(), 'namespace': 'okf'})),
        rejectedAt('namespace', 'fails not'),
      );
    });
  });

  test('every finding in the goldens is declared by its release', () {
    final goldens = Directory('test/goldens').listSync().whereType<File>();
    final seen = <String>{};
    for (final golden in goldens) {
      final profile =
          (jsonDecode(golden.readAsStringSync())
                  as Map<String, Object?>)['profile']
              as Map<String, Object?>;
      final release = profile['release'] as String?;
      final declared = {
        for (final descriptor in DispatchRule.all) descriptor.id,
        if (catalogs[release] case final catalog?)
          for (final rule in catalog.rules) rule.descriptor.id,
      };
      for (final finding in profile['findings'] as List<Object?>) {
        final id = (finding as Map<String, Object?>)['id'] as String;
        seen.add(id);
        expect(
          declared,
          contains(id),
          reason: '$id in ${p.basename(golden.path)} (release $release)',
        );
      }
    }
    expect(seen, isNotEmpty);
  });

  test('every rule of every release reports under its namespace', () {
    for (final MapEntry(key: release, value: catalog) in catalogs.entries) {
      expect(catalog.release, release);
      expect(catalog.profileId, builtinProfileId);
      for (final rule in catalog.rules) {
        expect(
          rule.descriptor.id,
          startsWith('${catalog.namespace}/'),
          reason: rule.descriptor.id,
        );
      }
    }
  });

  for (final MapEntry(key: release, value: catalog) in catalogs.entries) {
    for (final rule in catalog.rules) {
      test('$release ${rule.descriptor.id} examples behave as declared', () {
        expect(rule.failingExamples(), isEmpty);
      });
    }
  }

  test('load rejects a rule that reaches an unknown slot', () {
    expect(
      () => RuleCatalog.parse(
        jsonEncode({
          'format': 1,
          'namespace': 'x',
          'profile': {'id': 'x', 'release': '2026.1'},
          r'$defs': {
            'name': {'x-slot': 'profile.names'},
          },
          'rules': [
            {
              'id': 'a',
              'category': 'vocabulary',
              'severity': 'error',
              'status': 'stable',
              'ref': '§1',
              'description': 'd',
              'message': 'm',
              'check': {
                'subject': 'concept',
                'schema': {
                  'properties': {
                    'type': {r'$ref': r'#/$defs/name'},
                  },
                },
              },
              'tests': {
                'valid': [<String, Object?>{}],
                'invalid': [<String, Object?>{}],
              },
            },
          ],
        }),
      ),
      throwsA(
        isA<RuleCatalogException>().having(
          (error) => error.message,
          'message',
          contains('unknown slot'),
        ),
      ),
    );
  });
}
