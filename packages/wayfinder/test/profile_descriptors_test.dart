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
        rejectedAt('rules[0].severity', 'must be one of error, advisory, note'),
      );
    });

    test('a note severity, which reports summary entries', () {
      final rule = RuleCatalog.parse(
        jsonEncode(catalog(rule: {'severity': 'note'})),
      ).rules.single;
      expect(rule.descriptor.severity, RuleSeverity.note);
      expect(rule.descriptor.severity.finding, isNull);
    });

    test('link-graph-unavailable params other than a report path', () {
      final reported = RuleCatalog.parse(
        jsonEncode(
          catalog(
            rule: {
              'check': {
                'builtin': 'link-graph-unavailable',
                'params': {'path': 'index.md'},
              },
            },
          ),
        ),
      );
      expect(reported.rules.single.check, isA<BuiltinCheck>());
      expect(
        () => RuleCatalog.parse(
          jsonEncode(
            catalog(
              rule: {
                'check': {
                  'builtin': 'link-graph-unavailable',
                  'params': {'at': 'index.md'},
                },
              },
            ),
          ),
        ),
        rejectedAt('rules[0].check.params', 'params do not match'),
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

    group('a source catalog', () {
      const manifest = (id: 'client_profile', release: '2026.3');
      Map<String, Object?> source({
        String namespace = 'client-profile',
        String id = 'client_profile',
        String release = '2026.3',
        Map<String, Object?> extra = const {},
      }) => {
        ...catalog(release: release),
        'namespace': namespace,
        'profile': {'id': id, 'release': release},
        ...extra,
      };

      test('reports in the namespace its Profile identity derives', () {
        final parsed = RuleCatalog.parse(
          jsonEncode(source()),
          manifest: manifest,
        );
        expect(parsed.namespace, 'client-profile');
        expect(parsed.rules.single.descriptor.id, 'client-profile/a');
        expect(
          () => RuleCatalog.parse(
            jsonEncode(source(namespace: 'client')),
            manifest: manifest,
          ),
          rejectedAt('namespace', 'client-profile'),
        );
      });

      test('cannot claim the installed namespace', () {
        expect(
          () => RuleCatalog.parse(
            jsonEncode(
              source(namespace: 'concepta-profile', id: 'concepta_profile'),
            ),
            manifest: (id: 'concepta_profile', release: '2026.3'),
          ),
          rejectedAt('namespace', 'reserved'),
        );
      });

      test('must declare the manifest identity', () {
        expect(
          () => RuleCatalog.parse(
            jsonEncode(source(release: '2026.4')),
            manifest: manifest,
          ),
          rejectedAt('profile', 'client_profile/2026.3'),
        );
        expect(
          () => RuleCatalog.parse(
            jsonEncode(source(namespace: 'other', id: 'other')),
            manifest: manifest,
          ),
          rejectedAt('namespace', 'client-profile'),
        );
      });

      test('declares no frontmatter keys', () {
        expect(
          () => RuleCatalog.parse(
            jsonEncode(
              source(
                extra: {
                  'frontmatter_keys': {'owner': 'The owning team.'},
                },
              ),
            ),
            manifest: manifest,
          ),
          rejectedAt('frontmatter_keys', 'installed release'),
        );
      });
    });
  });

  test('2026.2 reports no summary entries', () {
    expect(
      catalogs[legacyProfileRelease]!.rules.map(
        (rule) => rule.descriptor.severity,
      ),
      everyElement(isNot(RuleSeverity.note)),
    );
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
        for (final descriptor in DispatchRule.all)
          descriptor.id: descriptor.severity,
        if (catalogs[release] case final catalog?)
          for (final rule in catalog.rules)
            rule.descriptor.id: rule.descriptor.severity,
      };
      for (final (key, isNote) in [('findings', false), ('summary', true)]) {
        for (final result in profile[key] as List<Object?>? ?? const []) {
          final id = (result as Map<String, Object?>)['id'] as String;
          seen.add(id);
          expect(
            declared.containsKey(id) &&
                (declared[id] == RuleSeverity.note) == isNote,
            isTrue,
            reason: '$id in ${p.basename(golden.path)} $key (release $release)',
          );
        }
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
