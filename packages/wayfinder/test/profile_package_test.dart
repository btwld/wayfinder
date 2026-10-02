import 'dart:convert';
import 'dart:io';

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
