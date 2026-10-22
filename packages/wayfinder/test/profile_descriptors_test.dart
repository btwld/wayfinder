import 'dart:convert';
import 'dart:io';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/rules/builtins.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('every finding in the goldens is declared by the Bitwild package', () {
    final declared = {
      for (final rule in bitwild.rules)
        rule.descriptor.id: rule.descriptor.severity,
    };
    final goldens = Directory('test/goldens').listSync().whereType<File>();
    final seen = <String>{};
    for (final golden in goldens) {
      final profile =
          (jsonDecode(golden.readAsStringSync())
                  as Map<String, Object?>)['profile']
              as Map<String, Object?>;
      for (final (key, isNote) in [('findings', false), ('summary', true)]) {
        for (final result in profile[key] as List<Object?>? ?? const []) {
          final id = (result as Map<String, Object?>)['id'] as String;
          seen.add(id);
          expect(
            declared.containsKey(id) &&
                (declared[id] == RuleSeverity.note) == isNote,
            isTrue,
            reason: '$id in ${p.basename(golden.path)} $key',
          );
          expect(
            result['help_uri'],
            '${declared.containsKey(id) ? bitwild.docs : null}#'
            '${id.substring('bitwild-profile/'.length)}',
            reason: '$id in ${p.basename(golden.path)} $key',
          );
        }
      }
    }
    expect(seen, isNotEmpty);
  });

  group('compile checks what the package schema cannot see', () {
    Map<String, Object?> builtinRule({
      required Map<String, Object?> check,
      Object message = 'm',
      String severity = 'error',
      Map<String, Object?> extra = const {},
    }) => {
      'id': 'a',
      'category': 'structure',
      'severity': severity,
      'status': 'stable',
      'description': 'd',
      'message': message,
      'check': check,
      ...extra,
    };

    Matcher rejectedAt(String where, String message) => throwsA(
      isA<ProfilePackageException>()
          .having((error) => error.where, 'where', where)
          .having((error) => error.message, 'message', contains(message)),
    );

    test('an unknown severity, at the rule that carries it', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              builtinRule(
                check: {
                  'builtin': 'files-present',
                  'params': {
                    'paths': ['index.md'],
                  },
                },
                severity: 'x',
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].severity', 'must be one of error, advisory, note'),
      );
    });

    test('a note severity, which reports summary entries', () {
      final rule = ProfilePackage.parse(
        packageJson(
          rules: [
            builtinRule(
              check: {
                'builtin': 'files-present',
                'params': {
                  'paths': ['index.md'],
                },
              },
              severity: 'note',
            ),
          ],
        ),
      ).rules.single;
      expect(rule.descriptor.severity, RuleSeverity.note);
      expect(rule.descriptor.severity.finding, isNull);
    });

    test('an unknown key, named on its object', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              builtinRule(
                check: {
                  'builtin': 'files-present',
                  'params': {
                    'paths': ['index.md'],
                  },
                },
                extra: {'ref': '§1'},
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].ref', 'unknown property'),
      );
    });

    group('builtin params outside the params schema', () {
      final valid = <String, Map<String, Object?>>{
        'files-present': {
          'paths': ['index.md'],
        },
        'path-targets-exist': {
          'fields': ['resource'],
        },
        'matches-generated': {
          'generator': 'okf-index',
          'version': okfIndexGeneratorRevision,
          'keep': ['index.md'],
          'extra': 'ignore',
        },
      };
      final mutationsByConstraint = <String, Map<String, Map<String, Object?>>>{
        'files-present': {
          '/required': {},
          '/additionalProperties': {
            'paths': ['a'],
            'x': 1,
          },
          '/properties/paths/type': {'paths': 'a'},
          '/properties/paths/minItems': {'paths': <Object?>[]},
          '/properties/paths/uniqueItems': {
            'paths': ['a', 'a'],
          },
          '/properties/paths/items/type': {
            'paths': [1],
          },
          '/properties/paths/items/minLength': {
            'paths': [''],
          },
        },
        'path-targets-exist': {
          '/required': {},
          '/additionalProperties': {
            'fields': ['resource'],
            'x': 1,
          },
          '/properties/fields/type': {'fields': 'resource'},
          '/properties/fields/minItems': {'fields': <Object?>[]},
          '/properties/fields/uniqueItems': {
            'fields': ['resource', 'resource'],
          },
          '/properties/fields/items/type': {
            'fields': [1],
          },
          '/properties/fields/items/enum': {
            'fields': ['body'],
          },
        },
        'matches-generated': {
          '/required': {},
          '/additionalProperties': {'generator': 'okf-index', 'x': 1},
          '/properties/generator/type': {'generator': 1},
          '/properties/generator/const': {'generator': 'other'},
          '/properties/version/type': {'generator': 'okf-index', 'version': 1},
          '/properties/version/const': {
            'generator': 'okf-index',
            'version': '0.0.0',
          },
          '/properties/keep/type': {'generator': 'okf-index', 'keep': 'a'},
          '/properties/keep/uniqueItems': {
            'generator': 'okf-index',
            'keep': ['a', 'a'],
          },
          '/properties/keep/items/type': {
            'generator': 'okf-index',
            'keep': [1],
          },
          '/properties/keep/items/minLength': {
            'generator': 'okf-index',
            'keep': [''],
          },
          '/properties/extra/type': {'generator': 'okf-index', 'extra': 1},
          '/properties/extra/enum': {
            'generator': 'okf-index',
            'extra': 'bogus',
          },
        },
      };

      String package(String builtin, Map<String, Object?> params) =>
          packageJson(
            rules: [
              builtinRule(
                check: {'builtin': builtin, 'params': params},
                message: builtin == 'matches-generated'
                    ? {'stale': 's', 'extra': 'e'}
                    : 'm',
              ),
            ],
          );

      test('each params constraint keys a mutation, which another constraint '
          'may also reject', () {
        Iterable<String> constraints(Object? schema, String at) sync* {
          for (final MapEntry(:key, :value)
              in (schema! as Map<String, Object?>).entries) {
            switch (key) {
              case 'properties':
                for (final MapEntry(key: name, value: property)
                    in (value! as Map<String, Object?>).entries) {
                  yield* constraints(property, '$at/properties/$name');
                }
              case 'items':
                yield* constraints(value, '$at/items');
              default:
                yield '$at/$key';
            }
          }
        }

        const paramsTypeCheckedByPackageSchema = '/type';
        expect(mutationsByConstraint.keys.toSet(), builtins.keys.toSet());
        for (final MapEntry(key: builtin, value: builtinCheck)
            in builtins.entries) {
          expect(
            mutationsByConstraint[builtin]!.keys.toSet(),
            constraints(builtinCheck.params.toJsonSchema(), '').toSet()
              ..remove(paramsTypeCheckedByPackageSchema),
            reason: builtin,
          );
        }
      });

      for (final MapEntry(key: builtin, value: mutations)
          in mutationsByConstraint.entries) {
        test('$builtin accepts its valid params', () {
          expect(
            ProfilePackage.parse(
              package(builtin, valid[builtin]!),
            ).rules.single.check,
            isA<BuiltinCheck>(),
          );
        });
        for (final MapEntry(key: constraint, value: params)
            in mutations.entries) {
          test('$builtin $constraint ${jsonEncode(params)}', () {
            expect(
              () => ProfilePackage.parse(package(builtin, params)),
              rejectedAt('rules[0].check.params', 'params do not match'),
            );
          });
        }
      }

      test('a matches-generated version pinned to another generator revision '
          'names the revision this engine runs', () {
        expect(
          () => ProfilePackage.parse(
            package('matches-generated', {
              'generator': 'okf-index',
              'version': '0.4.0',
            }),
          ),
          rejectedAt(
            'rules[0].check.params',
            'params do not match what builtin matches-generated accepts; '
                'this wayfinder runs okf generator revision '
                '$okfIndexGeneratorRevision, not 0.4.0',
          ),
        );
        expect(
          () => ProfilePackage.parse(
            package('matches-generated', {
              'generator': 'okf-index',
              'version': okfIndexGeneratorRevision,
              'extra': 'bogus',
            }),
          ),
          throwsA(
            isA<ProfilePackageException>().having(
              (error) => error.message,
              'message',
              isNot(contains('generator revision')),
            ),
          ),
        );
      });
    });

    test('a builtin check with tests, or a schema check without', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              builtinRule(
                check: {
                  'builtin': 'files-present',
                  'params': {
                    'paths': ['index.md'],
                  },
                },
                extra: {
                  'tests': {
                    'valid': [1],
                    'invalid': [2],
                  },
                },
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].tests', 'takes no tests'),
      );
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              builtinRule(check: {'subject': 'root', 'schema': true}),
            ],
          ),
        ),
        rejectedAt('rules[0].tests', 'needs tests'),
      );
    });

    test('message ids that are not exactly the builtin\'s', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              builtinRule(
                check: {
                  'builtin': 'matches-generated',
                  'params': {'generator': 'okf-index'},
                },
                message: {'stale': 's'},
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].message', 'exactly stale, extra'),
      );
    });

    test('a placeholder the builtin does not fill', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              builtinRule(
                check: {
                  'builtin': 'path-targets-exist',
                  'params': {
                    'fields': ['resource'],
                  },
                },
                message: 'at {path}: {target}',
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].message', '{path} is not filled'),
      );
    });

    test('a rule that reaches an unknown slot', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            extra: {
              r'$defs': {
                'name': {r'$ref': r'#/$defs/profile.names'},
              },
            },
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: {
                  'properties': {
                    'type': {r'$ref': r'#/$defs/name'},
                  },
                },
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].check.schema', r'$ref target is not in $defs'),
      );
    });

    test('a slot the tests give no value for', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            extra: {
              r'$defs': {
                'type-name': {r'$ref': r'#/$defs/profile.types'},
              },
            },
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: {
                  'properties': {
                    'type': {r'$ref': r'#/$defs/type-name'},
                  },
                },
                valid: [
                  {'type': 'Guide'},
                ],
                invalid: [
                  {'type': 'Memo'},
                ],
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].tests.slots', 'profile.types'),
      );
    });

    test('each over a fact that is not a list', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: true,
                check: {'each': 'path'},
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].check.each', 'not a list fact of concept'),
      );
    });

    test('failing_field that is not an element field', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: true,
                check: {'each': 'tags', 'failing_field': 'label'},
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
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
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'actor',
                schema: {
                  'allOf': [
                    {
                      'required': ['name'],
                    },
                  ],
                },
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].check.schema', 'name is not a fact of actor'),
      );
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: {
                  'properties': {
                    'href': {'type': 'string'},
                  },
                },
                check: {'each': 'edges'},
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'href is not a field of concept.edges elements',
        ),
      );
      final nested = ProfilePackage.parse(
        packageJson(
          rules: [
            ruleJson(
              'a',
              subject: 'concept',
              schema: {
                'properties': {
                  'tags': {
                    'items': {
                      'required': ['label'],
                    },
                  },
                },
              },
              valid: [
                {
                  'tags': [
                    {'label': 'x'},
                  ],
                },
              ],
              invalid: [
                {
                  'tags': [<String, Object?>{}],
                },
              ],
            ),
          ],
        ),
      );
      expect(nested.rules, hasLength(1), reason: 'names below a descent');
    });

    test('a name reached through \$ref is checked as if it were inline', () {
      const typo = {
        'required': ['typo_path'],
      };
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: {
                  r'$defs': {'shape': typo},
                  r'$ref': r'#/$defs/shape',
                },
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'typo_path is not a fact of concept',
        ),
        reason: 'a rule-local def',
      );
      expect(
        () => ProfilePackage.parse(
          packageJson(
            extra: {
              r'$defs': {
                'outer': {r'$ref': r'#/$defs/shape'},
                'shape': typo,
              },
            },
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: {
                  'anyOf': [
                    {r'$ref': r'#/$defs/outer'},
                  ],
                },
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'typo_path is not a fact of concept',
        ),
        reason: 'a package def reached through another def',
      );
      final nested = ProfilePackage.parse(
        packageJson(
          extra: {
            r'$defs': {
              'tag': {
                'required': ['label'],
              },
            },
          },
          rules: [
            ruleJson(
              'a',
              subject: 'concept',
              schema: {
                'properties': {
                  'tags': {
                    'items': {r'$ref': r'#/$defs/tag'},
                  },
                },
              },
              valid: [
                {
                  'tags': [
                    {'label': 'x'},
                  ],
                },
              ],
              invalid: [
                {
                  'tags': [<String, Object?>{}],
                },
              ],
            ),
          ],
        ),
      );
      expect(nested.rules, hasLength(1), reason: 'a def used below a descent');
    });

    test('frontmatter stays open', () {
      final open = ProfilePackage.parse(
        packageJson(
          rules: [
            ruleJson(
              'a',
              subject: 'frontmatter',
              schema: {
                'required': ['whatever'],
              },
              check: {'each': 'anything', 'failing_field': 'whatever'},
              valid: [
                {'whatever': 1},
              ],
              invalid: [<String, Object?>{}],
            ),
          ],
        ),
      );
      expect(open.rules, hasLength(1));
    });

    test('a location the subject does not have', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: true,
                check: {'at': 'index'},
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].check.at', 'not a location of concept'),
      );
    });
  });
}
