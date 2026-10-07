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

  group('load checks what the catalog schema cannot see', () {
    Map<String, Object?> schemaRule({
      required Map<String, Object?> check,
      Map<String, Object?> tests = const {
        'valid': [<String, Object?>{}],
        'invalid': [<String, Object?>{}],
      },
      Object message = 'm',
    }) => {
      'id': 'a',
      'category': 'structure',
      'severity': 'error',
      'status': 'stable',
      'ref': '§1',
      'description': 'd',
      'message': message,
      'check': check,
      if (check.containsKey('subject')) 'tests': tests,
    };

    String catalog(
      Map<String, Object?> rule, {
      String release = '2026.1',
      Map<String, Object?>? defs,
    }) => jsonEncode({
      'format': 1,
      'namespace': 'x',
      'profile': {'id': 'x', 'release': release},
      r'$defs': ?defs,
      'rules': [rule],
    });

    Matcher rejectedAt(String where, String message) => throwsA(
      isA<RuleCatalogException>()
          .having((error) => error.where, 'where', where)
          .having((error) => error.message, 'message', contains(message)),
    );

    test('a rule whose examples disagree with its schema', () {
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'subject': 'actor',
                'schema': {
                  'properties': {
                    'id': {'const': 'a'},
                  },
                },
              },
              tests: {
                'valid': [
                  {'id': 'b'},
                ],
                'invalid': [
                  {'id': 'a'},
                  {'id': 'c'},
                ],
              },
            ),
          ),
        ),
        rejectedAt('rules[0].tests', 'valid[0] fails, invalid[0] passes'),
      );
    });

    test('each over a fact that is not a list', () {
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {'subject': 'concept', 'each': 'path', 'schema': true},
            ),
          ),
        ),
        rejectedAt('rules[0].check.each', 'not a list fact of concept'),
      );
    });

    test('failing_field that is not an element field', () {
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'subject': 'concept',
                'each': 'tags',
                'failing_field': 'label',
                'schema': true,
              },
            ),
          ),
        ),
        rejectedAt(
          'rules[0].check.failing_field',
          'not a field of concept.tags elements',
        ),
      );
    });

    test('a property or required name no fact or element field carries', () {
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'subject': 'actor',
                'schema': {
                  'allOf': [
                    {
                      'required': ['name'],
                    },
                  ],
                },
              },
            ),
          ),
        ),
        rejectedAt('rules[0].check.schema', 'name is not a fact of actor'),
      );
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'subject': 'concept',
                'each': 'edges',
                'schema': {
                  'properties': {
                    'href': {'type': 'string'},
                  },
                },
              },
            ),
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'href is not a field of concept.edges elements',
        ),
      );
      final nested = RuleCatalog.parse(
        catalog(
          schemaRule(
            check: {
              'subject': 'concept',
              'schema': {
                'properties': {
                  'tags': {
                    'items': {
                      'required': ['label'],
                    },
                  },
                },
              },
            },
            tests: {
              'valid': [
                {
                  'tags': [
                    {'label': 'x'},
                  ],
                },
              ],
              'invalid': [
                {
                  'tags': [<String, Object?>{}],
                },
              ],
            },
          ),
        ),
      );
      expect(nested.rules, hasLength(1), reason: 'names below a descent');
    });

    test('a name reached through \$ref is checked as if it were inline', () {
      const typo = {
        'required': ['typo_path'],
      };
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'subject': 'concept',
                'schema': {
                  r'$defs': {'shape': typo},
                  r'$ref': r'#/$defs/shape',
                },
              },
            ),
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'typo_path is not a fact of concept',
        ),
        reason: 'a rule-local def',
      );
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'subject': 'concept',
                'schema': {
                  'anyOf': [
                    {r'$ref': r'#/$defs/outer'},
                  ],
                },
              },
            ),
            defs: {
              'outer': {r'$ref': r'#/$defs/shape'},
              'shape': typo,
            },
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'typo_path is not a fact of concept',
        ),
        reason: 'a catalog def reached through another def',
      );
      final nested = RuleCatalog.parse(
        catalog(
          schemaRule(
            check: {
              'subject': 'concept',
              'schema': {
                'properties': {
                  'tags': {
                    'items': {r'$ref': r'#/$defs/tag'},
                  },
                },
              },
            },
            tests: {
              'valid': [
                {
                  'tags': [
                    {'label': 'x'},
                  ],
                },
              ],
              'invalid': [
                {
                  'tags': [<String, Object?>{}],
                },
              ],
            },
          ),
          defs: {
            'tag': {
              'required': ['label'],
            },
          },
        ),
      );
      expect(nested.rules, hasLength(1), reason: 'a def used below a descent');
    });

    test('frontmatter stays open', () {
      final open = RuleCatalog.parse(
        catalog(
          schemaRule(
            check: {
              'subject': 'frontmatter',
              'each': 'anything',
              'failing_field': 'whatever',
              'schema': {
                'required': ['whatever'],
              },
            },
            tests: {
              'valid': [
                {'whatever': 1},
              ],
              'invalid': [<String, Object?>{}],
            },
          ),
        ),
      );
      expect(open.rules, hasLength(1));
    });

    test('params for a builtin that takes none', () {
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {
                'builtin': 'index-current',
                'params': {'x': 1},
              },
            ),
          ),
        ),
        rejectedAt('rules[0].check.params', 'do not match'),
      );
    });

    test('a placeholder the builtin does not fill', () {
      expect(
        () => RuleCatalog.parse(
          catalog(
            schemaRule(
              check: {'builtin': 'link-graph-unavailable'},
              message: 'at {path}: {error}',
            ),
          ),
        ),
        rejectedAt('rules[0].message', '{path} is not filled'),
      );
    });

    test('a 2026.2 builtin outside the installed 2026.2 catalog', () {
      for (final release in ['2026.1', legacyProfileRelease]) {
        expect(
          () => RuleCatalog.parse(
            catalog(
              schemaRule(check: {'builtin': 'type-registry-present'}),
              release: release,
            ),
          ),
          rejectedAt(
            'rules[0].check.builtin',
            'only the installed 2026.2 catalog',
          ),
          reason: release,
        );
      }
      expect(
        catalogs[legacyProfileRelease]!.rules
            .map((rule) => rule.check)
            .whereType<BuiltinCheck>()
            .map((check) => check.name),
        contains('type-registry-present'),
      );
    });
  });
}
