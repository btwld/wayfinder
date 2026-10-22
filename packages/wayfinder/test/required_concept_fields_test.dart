import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test("Bitwild's required concept fields come from its rules", () {
    expect(EffectiveProfile.compose([bitwild]).requiredConceptFields, [
      'type',
      'title',
      'description',
      'status',
    ]);
  });

  test('only error frontmatter rules that require a key unconditionally '
      'count', () {
    final probe = ProfilePackage.parse(
      packageJson(
        rules: [
          ruleJson(
            'baseline',
            subject: 'frontmatter',
            schema: {
              'required': ['owner'],
              'allOf': [
                {r'$ref': r'#/$defs/reviewed'},
              ],
              r'$defs': {
                'reviewed': {
                  'required': ['reviewed'],
                },
              },
            },
            valid: [
              {'owner': 'a', 'reviewed': 'b'},
            ],
            invalid: [<String, Object?>{}],
          ),
          ruleJson(
            'again',
            subject: 'frontmatter',
            schema: {
              'required': ['reviewed', 'audience'],
            },
            valid: [
              {'reviewed': 'b', 'audience': 'c'},
            ],
            invalid: [<String, Object?>{}],
          ),
          ruleJson(
            'recommended',
            subject: 'frontmatter',
            severity: 'advisory',
            schema: {
              'required': ['summary'],
            },
            valid: [
              {'summary': 'a'},
            ],
            invalid: [<String, Object?>{}],
          ),
          ruleJson(
            'conditional',
            subject: 'frontmatter',
            schema: {
              'if': {
                'required': ['status'],
              },
              'then': {
                'required': ['since'],
              },
              'anyOf': [
                {
                  'required': ['alias'],
                },
                {
                  'required': ['name'],
                },
              ],
            },
            valid: [
              {'alias': 'a'},
            ],
            invalid: [
              {'status': 'stable', 'alias': 'a'},
            ],
          ),
          ruleJson(
            'concept-facts',
            subject: 'concept',
            schema: {
              'required': ['type'],
            },
            valid: [
              {'type': 'a'},
            ],
            invalid: [<String, Object?>{}],
          ),
        ],
      ),
    );
    expect(EffectiveProfile.compose([probe]).requiredConceptFields, [
      'owner',
      'reviewed',
      'audience',
    ]);
  });

  test('a chain lists its root ancestor first and each key once', () {
    final child = ProfilePackage.parse(
      packageJson(
        id: 'client-profile',
        extra: {
          'extends': {'path': 'profiles/bitwild'},
        },
        rules: [
          ruleJson(
            'owned',
            subject: 'frontmatter',
            schema: {
              'required': ['title', 'owner'],
            },
            valid: [
              {'title': 'a', 'owner': 'b'},
            ],
            invalid: [<String, Object?>{}],
          ),
        ],
      ),
    );
    final profile = EffectiveProfile.compose([bitwild, child]);
    expect(profile.requiredConceptFields, [
      'type',
      'title',
      'description',
      'status',
      'owner',
    ]);
    expect(
      () => profile.requiredConceptFields.add('more'),
      throwsUnsupportedError,
    );
  });

  test('a Profile without such a rule requires no field', () {
    expect(
      EffectiveProfile.compose([
        ProfilePackage.parse(packageJson()),
      ]).requiredConceptFields,
      isEmpty,
    );
  });
}
