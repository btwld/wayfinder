import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/generated/published_schemas.g.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('the embedded schemas are the published ones', () async {
    for (final (path, embedded) in [
      ('wayfinder.schema.json', wayfinderConfigurationSchema),
      ('wayfinder-profile.schema.json', wayfinderProfileSchema),
    ]) {
      expect(
        embedded,
        await File('../../docs/schemas/$path').readAsString(),
        reason: '$path; run dart run tool/generate_published_schemas.dart',
      );
    }
  });

  test('Bitwild is read by the same boundary as any package', () {
    expect(bitwild.id, ProfileId.parse('bitwild-profile'));
    expect(bitwild.release, '2026.3');
    expect(bitwild.okfRelease, '0.2');
    expect(bitwild.types, hasLength(12));
    expect(bitwild.tags, isEmpty);
    expect(bitwild.relationships, hasLength(11));
    expect(bitwild.frontmatterKeys.map((key) => key.name), ['relationships']);
    expect(bitwild.rules, hasLength(27));
    expect(
      bitwild.rules.map((rule) => rule.descriptor.id),
      everyElement(startsWith('bitwild-profile/')),
    );
    expect(
      bitwild.rules.first.descriptor.helpUri,
      Uri.parse(
        'https://github.com/btwld/wayfinder/blob/main/profiles/bitwild/'
        'README.md#okf-release-binding',
      ),
    );
    expect(
      bitwild.rules.map((rule) => rule.descriptor.helpUri?.fragment),
      bitwild.rules.map(
        (rule) => rule.descriptor.id.substring('bitwild-profile/'.length),
      ),
    );
  });

  test('every skill directory name a Profile would shadow is reserved', () {
    final skills = Directory(p.join('..', '..', 'skills'))
        .listSync()
        .whereType<Directory>()
        .map((directory) => p.basename(directory.path))
        .toList();
    expect(skills, isNotEmpty);
    for (final name in [...skills, 'synced', 'anthropic-skills']) {
      expect(ProfileId.reserved, contains(name), reason: name);
      expect(() => ProfileId.parse(name), throwsFormatException, reason: name);
    }
  });

  Matcher rejectedAt(String where, String message, {bool? unsupported}) =>
      throwsA(
        isA<ProfilePackageException>()
            .having((error) => error.where, 'where', where)
            .having((error) => error.message, 'message', contains(message))
            .having(
              (error) => error.unsupported,
              'unsupported',
              unsupported ?? anything,
            ),
      );

  group('parse refuses whole what this engine cannot evaluate', () {
    test('another package format, before any schema check', () {
      final json = jsonDecode(packageJson()) as Map<String, Object?>;
      json['format'] = 3;
      json['surprise'] = true;
      expect(
        () => ProfilePackage.parse(jsonEncode(json)),
        rejectedAt('format', 'format 3 is not supported', unsupported: true),
      );
    });

    test('an OKF release its okf cannot read', () {
      final json = jsonDecode(packageJson()) as Map<String, Object?>;
      json['implements'] = {'id': 'okf', 'release': '0.3'};
      expect(
        () => ProfilePackage.parse(jsonEncode(json)),
        rejectedAt(
          'implements.release',
          'OKF 0.3 is not supported',
          unsupported: true,
        ),
      );
    });

    test('a schema keyword or format outside the engine subset', () {
      for (final (schema, message) in [
        (
          {'patternProperties': <String, Object?>{}},
          'unsupported keyword "patternProperties"',
        ),
        (
          {
            'properties': {
              'path': {'format': 'email'},
            },
          },
          'only format "date-time" is supported',
        ),
      ]) {
        expect(
          () => ProfilePackage.parse(
            packageJson(
              rules: [
                ruleJson(
                  'a',
                  subject: 'concept',
                  schema: schema,
                  valid: [<String, Object?>{}],
                  invalid: [<String, Object?>{}],
                ),
              ],
            ),
          ),
          rejectedAt('rules[0].check.schema', message, unsupported: true),
          reason: message,
        );
      }
    });

    test('a builtin it does not provide', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              {
                'id': 'a',
                'category': 'structure',
                'severity': 'error',
                'status': 'stable',
                'description': 'd',
                'message': 'm',
                'check': {'builtin': 'nonexistent-check'},
              },
            ],
          ),
        ),
        rejectedAt(
          'rules[0].check.builtin',
          'unknown builtin nonexistent-check',
          unsupported: true,
        ),
      );
    });
  });

  group('parse rejects a malformed package, naming where', () {
    test('text that is not JSON', () {
      expect(
        () => ProfilePackage.parse('{'),
        rejectedAt('package', '', unsupported: false),
      );
    });

    test('a rule schema ref with a malformed percent escape', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'concept',
                schema: {r'$ref': r'#/$defs/%zz'},
                valid: [<String, Object?>{}],
                invalid: [<String, Object?>{}],
              ),
            ],
          ),
        ),
        rejectedAt(
          'rules[0].check.schema',
          'has a malformed percent escape',
          unsupported: false,
        ),
      );
    });

    test('a missing required key, named', () {
      final json = jsonDecode(packageJson()) as Map<String, Object?>;
      json.remove('release');
      expect(
        () => ProfilePackage.parse(jsonEncode(json)),
        rejectedAt('release', 'missing required property release'),
      );
    });

    test('an id outside the finding-namespace grammar', () {
      for (final id in ['client_profile', 'Client', '1st', 'a--b', 'a-']) {
        expect(
          () => ProfilePackage.parse(packageJson(id: id)),
          rejectedAt('id', 'must be a Profile id'),
          reason: id,
        );
      }
    });

    test('an id longer than an Agent Skills name', () {
      final longest = 'a' * ProfileId.maxLength;
      expect(ProfilePackage.parse(packageJson(id: longest)).id.value, longest);
      expect(
        () => ProfilePackage.parse(packageJson(id: '${longest}b')),
        rejectedAt('id', 'must have at most 64 characters'),
      );
      expect(
        () => ProfileId.parse('${longest}b'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'a Profile id has at most 64 characters',
          ),
        ),
      );
    });

    test('a reserved id', () {
      for (final id in ProfileId.reserved) {
        expect(
          () => ProfilePackage.parse(packageJson(id: id)),
          rejectedAt('id', '$id is reserved', unsupported: false),
          reason: id,
        );
      }
    });

    test('a release outside the release grammar', () {
      expect(
        () => ProfilePackage.parse(packageJson(release: '-1')),
        rejectedAt('release', 'must be a release name'),
      );
      expect(
        ProfilePackage.parse(packageJson(release: 'v1.0+rc')).release,
        'v1.0+rc',
      );
    });

    test('a name repeated within one noun', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            extra: {
              'types': [
                {'name': 'Guide', 'description': 'a'},
                {'name': 'Guide', 'description': 'b'},
              ],
            },
          ),
        ),
        rejectedAt('types', 'repeats the name Guide'),
      );
    });

    test('a frontmatter key OKF already defines', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            extra: {
              'frontmatter_keys': [
                {'name': 'sources', 'description': 'Provenance, again.'},
              ],
            },
          ),
        ),
        rejectedAt(
          'frontmatter_keys',
          'OKF frontmatter key',
          unsupported: false,
        ),
      );
    });

    test('a docs value that is not an absolute URI', () {
      expect(
        () => ProfilePackage.parse(packageJson(extra: {'docs': 'README.md'})),
        rejectedAt('docs', 'must be an absolute URI'),
      );
      // Passes the schema pattern, but is not a URI Dart can parse.
      expect(
        () =>
            ProfilePackage.parse(packageJson(extra: {'docs': 'https://[::1'})),
        rejectedAt('docs', 'is not a valid URI', unsupported: false),
      );
    });

    test('an extends that is neither parent shape', () {
      for (final parent in [
        {'git': 'https://example.test/p.git', 'path': 'profiles/base'},
        {'ref': 'v1', 'path': 'profiles/base'},
        {'path': '../base'},
        {'git': '../sibling', 'ref': 'v1', 'path': 'profiles/base'},
      ]) {
        expect(
          () => ProfilePackage.parse(packageJson(extra: {'extends': parent})),
          rejectedAt('extends', 'must match exactly one of its allowed shapes'),
          reason: '$parent',
        );
      }
      expect(
        () => ProfilePackage.parse(
          packageJson(
            extra: {
              'extends': {
                'git': 'https://user:secret@example.test/p.git',
                'ref': 'v1',
                'path': 'profiles/base',
              },
            },
          ),
        ),
        rejectedAt('extends.git', 'must not contain credentials'),
      );
    });

    test('a skill outside the package', () {
      for (final skill in ['../skill', '/skill', 'C:/skill']) {
        expect(
          () => ProfilePackage.parse(packageJson(extra: {'skill': skill})),
          rejectedAt('skill', 'a relative path without parent traversal'),
          reason: skill,
        );
      }
    });

    test('a rule whose own examples disagree with its check', () {
      expect(
        () => ProfilePackage.parse(
          packageJson(
            rules: [
              ruleJson(
                'a',
                subject: 'actor',
                schema: {
                  'properties': {
                    'id': {'const': 'a'},
                  },
                },
                valid: [
                  {'id': 'b'},
                ],
                invalid: [
                  {'id': 'a'},
                  {'id': 'c'},
                ],
              ),
            ],
          ),
        ),
        rejectedAt('rules[0].tests', 'valid[0] fails, invalid[0] passes'),
      );
    });

    test('a duplicate rule id', () {
      final rule = ruleJson(
        'a',
        subject: 'root',
        schema: true,
        valid: [<String, Object?>{}],
        invalid: [
          {'okf_version': 1},
        ],
      );
      (rule['tests']! as Map<String, Object?>)['invalid'] = [
        <String, Object?>{},
      ];
      expect(
        () => ProfilePackage.parse(packageJson(rules: [rule, rule])),
        rejectedAt('rules[0].tests', 'invalid[0] passes'),
      );
    });
  });

  test('a package names its parent at the same or another revision', () {
    expect(ProfilePackage.parse(packageJson()).parent, isNull);
    final same = ProfilePackage.parse(
      packageJson(
        extra: {
          'extends': {'path': './profiles/bitwild'},
        },
      ),
    );
    expect(
      same.parent,
      isA<SameRevision>().having(
        (parent) => parent.path,
        'path',
        'profiles/bitwild',
      ),
    );
    final other = ProfilePackage.parse(
      packageJson(
        extra: {
          'extends': {
            'git': 'git@example.test:acme/profiles.git',
            'ref': 'v2026.3',
            'path': 'profiles/bitwild/',
          },
        },
      ),
    );
    final source = (other.parent! as OtherRevision).source;
    expect(
      (source.git, source.ref, source.path),
      ('git@example.test:acme/profiles.git', 'v2026.3', 'profiles/bitwild'),
    );
  });

  test('a package names its skill directory relative to itself', () {
    expect(
      ProfilePackage.parse(
        packageJson(extra: {'skill': './agent/skill/'}),
      ).skill,
      'agent/skill',
    );
  });

  test('the id is the finding namespace and the help link is derived', () {
    final rule = ruleJson(
      'known-type',
      subject: 'concept',
      schema: {
        'properties': {
          'type': {'const': 'Runbook'},
        },
      },
      valid: [
        {'type': 'Runbook'},
      ],
      invalid: [
        {'type': 'Memo'},
      ],
    );
    final documented = ProfilePackage.parse(
      packageJson(
        id: 'acme-notes',
        rules: [rule],
        extra: {'docs': 'https://acme.example/notes/README.md'},
      ),
    );
    expect(documented.rules.single.descriptor.id, 'acme-notes/known-type');
    expect(
      documented.rules.single.descriptor.helpUri,
      Uri.parse('https://acme.example/notes/README.md#known-type'),
    );
    final undocumented = ProfilePackage.parse(
      packageJson(id: 'acme-notes', rules: [rule]),
    );
    expect(undocumented.docs, isNull);
    expect(undocumented.rules.single.descriptor.helpUri, isNull);
  });
}
