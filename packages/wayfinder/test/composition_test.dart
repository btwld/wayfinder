import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

final acme = ProfilePackage.parse(
  jsonEncode({
    'format': 2,
    'id': 'acme-notes',
    'release': '1.0',
    'implements': {'id': 'okf', 'release': '0.2'},
    'docs': 'https://git.acme.example/notes-profile/blob/v1.0/README.md',
    'types': [
      {'name': 'Runbook', 'description': 'Steps to operate a running system'},
    ],
    'rules': [
      {
        'id': 'known-type',
        'category': 'vocabulary',
        'severity': 'error',
        'status': 'stable',
        'description': 'Every concept type MUST be declared.',
        'message': 'Type {type} is not declared.',
        'check': {
          'subject': 'concept',
          'schema': {
            'properties': {
              'type': {r'$ref': r'#/$defs/type-name'},
            },
          },
        },
        'tests': {
          'slots': {
            'profile.types': ['Runbook'],
          },
          'valid': [
            {'type': 'Runbook'},
          ],
          'invalid': [
            {'type': 'Memo'},
          ],
        },
      },
      {
        'id': 'index-current',
        'category': 'structure',
        'severity': 'error',
        'status': 'stable',
        'description': "Every index.md MUST equal okf's generated index.",
        'message': {
          'stale': "{path} is not okf's generated index.",
          'extra': '{path} is not generated.',
        },
        'check': {
          'builtin': 'matches-generated',
          'params': {
            'generator': 'okf-index',
            'keep': ['index.md'],
          },
        },
      },
    ],
    r'$defs': {
      'type-name': {'x-slot': 'profile.types'},
    },
  }),
);

final child = ProfilePackage.parse(
  packageJson(
    id: 'client-profile',
    release: '2026.3',
    extra: {'docs': 'https://client.example/profile/README.md'},
    rules: [
      ruleJson(
        'title-never',
        subject: 'frontmatter',
        schema: {
          'properties': {
            'title': {'const': '~never~'},
          },
          'required': ['title'],
        },
        valid: [
          {'title': '~never~'},
        ],
        invalid: [
          {'title': 'Sample'},
        ],
        message: 'Client rule title-never.',
      ),
      ruleJson(
        'root-never',
        subject: 'root',
        severity: 'advisory',
        schema: {
          'properties': {
            'files': {
              'items': {
                'not': {'const': 'index.md'},
              },
            },
          },
        },
        valid: [
          {'files': <String>[]},
        ],
        invalid: [
          {
            'files': <String>['index.md'],
          },
        ],
        message: 'Client rule root-never.',
      ),
      ruleJson(
        'concept-seen',
        subject: 'concept',
        severity: 'note',
        schema: {
          'properties': {
            'path': {'const': '~never~'},
          },
        },
        valid: [
          {'path': '~never~'},
        ],
        invalid: [
          {'path': 'a.md'},
        ],
        message: 'Client rule concept-seen.',
      ),
    ],
  ),
);

bool _bitwild(String id) => id.startsWith('bitwild-profile/');

const _fixturesWithoutRootIndex = {'missing-structure-root'};
const _fixturesWithoutConcept = {'empty-root-index'};

void main() {
  group('a Profile with no Bitwild validates end to end', () {
    late Directory project;
    late String bundle;
    late String configPath;
    late WayfinderProjectConfig config;

    setUp(() async {
      project = await copyFixture('configured-project');
      configPath = p.join(project.path, 'wayfinder.json');
      bundle = p.join(project.path, 'knowledge');
      final json =
          jsonDecode(await File(configPath).readAsString())
              as Map<String, Object?>;
      final profiles = json['profiles']! as Map<String, Object?>;
      profiles['acme-notes'] = profiles.remove('bitwild-profile');
      await File(configPath).writeAsString(jsonEncode(json));
      config = WayfinderProjectConfig.parse(jsonEncode(json));
    });

    tearDown(() => project.delete(recursive: true));

    Future<ProfileValidationResult> validate(
      ProjectVocabulary project, {
      bool fix = false,
    }) => const ProfileValidator().validate(
      bundle,
      SelectedProfile(EffectiveProfile.compose([acme], project: project)),
      fix: fix,
    );

    test('and fails on its own rule', () async {
      final result = await validate(
        config.profiles[ProfileId.parse('acme-notes')]!.project,
      );
      expect(result.profileRelease, '1.0');
      expect(result.chain.map((package) => package.id), [acme.id]);
      expect(result.findings.map((finding) => finding.toJson()), [
        {
          'id': 'acme-notes/known-type',
          'severity': 'error',
          'message': 'Type Guide is not declared.',
          'location': {'path': 'sample.md'},
          'profile_release': '1.0',
          'help_uri':
              'https://git.acme.example/notes-profile/blob/v1.0/README.md'
              '#known-type',
        },
      ]);
      expect(result.gate, GateState.fail);
      expect(result.exitCode, 1);
      expect(
        result.toTextLines(),
        contains(
          'sample.md: error acme-notes/known-type (1.0): '
          'Type Guide is not declared.',
        ),
      );
    });

    test('and passes once the project declares the type', () async {
      final result = await validate(
        const ProjectVocabulary(
          types: [WayfinderDefinition(name: 'Guide', description: 'A guide')],
        ),
      );
      expect(result.findings, isEmpty);
      expect(result.summary, isNull, reason: 'acme declares no note rule');
      expect(result.diagnostics.map((d) => d.code), [
        DiagnosticCode.projectType,
      ]);
      expect(result.gate, GateState.pass);
      expect(result.toJson()['profile'], {
        'id': 'acme-notes',
        'release': '1.0',
        'chain': [
          {'id': 'acme-notes', 'release': '1.0'},
        ],
        'state': 'PASS',
        'findings': <Object?>[],
      });
    });

    test('and its generated-index rule fixes the bundle', () async {
      final index = File(p.join(bundle, 'index.md'));
      await index.writeAsString(
        (await index.readAsString()).replaceFirst(
          'A sample guide.',
          'An edited guide.',
        ),
      );
      final stale = await validate(
        const ProjectVocabulary(
          types: [WayfinderDefinition(name: 'Guide', description: 'A guide')],
        ),
      );
      expect(stale.findings.map((finding) => finding.id), [
        'acme-notes/index-current',
      ]);
      expect(
        stale.findings.single.message,
        "index.md is not okf's generated index.",
      );
      final fixed = await validate(
        const ProjectVocabulary(
          types: [WayfinderDefinition(name: 'Guide', description: 'A guide')],
        ),
        fix: true,
      );
      expect(fixed.fixed, ['index.md']);
      expect(fixed.findings, isEmpty);
      expect(
        await File(p.join(bundle, 'index.md')).readAsString(),
        startsWith('---\nokf_version: "0.2"\n---\n'),
      );
    });
  });

  group('a child package only adds findings in its own namespace', () {
    final fixtures =
        Directory(p.join('test', 'fixtures'))
            .listSync()
            .whereType<Directory>()
            .map((directory) => p.basename(directory.path))
            .toList()
          ..sort();
    var chained = 0;
    for (final name in fixtures.where(
      (n) => !_fixturesWithoutRootIndex.contains(n),
    )) {
      test(name, () async {
        final plain = await validateFixture(fixture(name));
        final composed = await validateFixture(
          fixture(name),
          children: [child],
        );
        expect(composed.okfReport.toJson(), plain.okfReport.toJson());
        expect(composed.profileRelease, plain.profileRelease);
        expect(
          composed.findings.where((f) => _bitwild(f.id)).map((f) => f.toJson()),
          plain.findings.map((f) => f.toJson()),
        );
        expect(
          composed.summary?.where((e) => _bitwild(e.id)).map((e) => e.toJson()),
          plain.summary?.map((e) => e.toJson()),
        );
        final added = composed.findings.where((f) => !_bitwild(f.id)).toList();
        expect(
          added.map((f) => f.id),
          everyElement(startsWith('client-profile/')),
        );
        expect(added.map((f) => f.profileRelease), everyElement('2026.3'));
        if (composed.chain case [_, final second]) {
          chained++;
          expect(identical(second, child), isTrue);
          expect(plain.chain, hasLength(1));
          expect(added.map((f) => f.id), contains('client-profile/root-never'));
          expect(
            composed.summary!.map((e) => e.id),
            _fixturesWithoutConcept.contains(name)
                ? isNot(contains('client-profile/concept-seen'))
                : contains('client-profile/concept-seen'),
          );
        } else {
          expect(composed.chain.length, plain.chain.length);
          expect(added, isEmpty);
        }
      });
    }

    test('at least one fixture was assessed with the chain', () {
      expect(chained, greaterThan(0));
    });
  });

  test('SARIF lists every package in the chain with its release', () async {
    final result = await validateFixture(
      fixture('configured-project'),
      children: [child],
    );
    final sarif = toSarif(
      result,
      bundlePath: fixtureBundle(fixture('configured-project')),
      toolVersion: 'test',
    );
    final runs = sarif['runs']! as List<Object?>;
    final tool =
        (runs.single! as Map<String, Object?>)['tool']! as Map<String, Object?>;
    final driver = tool['driver']! as Map<String, Object?>;
    final rules = {
      for (final rule
          in (driver['rules']! as List<Object?>).cast<Map<String, Object?>>())
        rule['id']! as String: rule,
    };
    expect(rules.keys, contains('bitwild-profile/okf-release-binding'));
    expect(rules['client-profile/title-never'], {
      'id': 'client-profile/title-never',
      'shortDescription': {'text': 'Client rule title-never.'},
      'helpUri': 'https://client.example/profile/README.md#title-never',
      'defaultConfiguration': {'level': 'error'},
      'properties': {'category': 'structure', 'profile_release': '2026.3'},
    });
    expect(rules['client-profile/concept-seen']!['defaultConfiguration'], {
      'level': 'none',
    });
    expect(tool['extensions'], [
      {'name': 'okf', 'version': okfPackageVersion},
    ]);
  });

  group('compose refuses', () {
    Matcher refused(String message) => throwsA(
      isA<ProfileCompositionException>().having(
        (error) => error.message,
        'message',
        message,
      ),
    );

    test('an empty chain or a repeated id', () {
      expect(
        () => EffectiveProfile.compose([]),
        refused('A Profile chain needs at least one package.'),
      );
      expect(
        () => EffectiveProfile.compose([bitwild, bitwild]),
        refused('Profile bitwild-profile appears twice in the chain.'),
      );
    });

    test('a name another contributor already declares, per noun', () {
      final repeats = ProfilePackage.parse(
        packageJson(
          id: 'repeats',
          extra: {
            'types': [
              {'name': 'Guide', 'description': 'Again'},
            ],
          },
        ),
      );
      expect(
        () => EffectiveProfile.compose([bitwild, repeats]),
        refused(
          'Profile repeats declares type Guide, which Profile '
          'bitwild-profile already declares.',
        ),
      );
      expect(
        () => EffectiveProfile.compose(
          [bitwild],
          project: const ProjectVocabulary(
            relationships: [
              WayfinderDefinition(name: 'depends-on', description: 'Again'),
            ],
          ),
        ),
        refused(
          'The project declares relationship depends-on, which Profile '
          'bitwild-profile already declares.',
        ),
      );
      final key = ProfilePackage.parse(
        packageJson(
          id: 'keyed',
          extra: {
            'frontmatter_keys': [
              {'name': 'relationships', 'description': 'Again'},
            ],
          },
        ),
      );
      expect(
        () => EffectiveProfile.compose([bitwild, key]),
        refused(
          'Profile keyed declares frontmatter key relationships, which '
          'Profile bitwild-profile already declares.',
        ),
      );
    });

    test('a tag that equals another vocabulary value', () {
      for (final (name, what) in [
        ('draft', 'an OKF status value'),
        ('human-reviewed', 'an OKF trust tier'),
        ('depends-on', 'a declared relationship name'),
        ('Guide', 'a declared type name'),
      ]) {
        expect(
          () => EffectiveProfile.compose(
            [bitwild],
            project: ProjectVocabulary(
              tags: [WayfinderDefinition(name: name, description: 'Collides')],
            ),
          ),
          refused('The project declares tag $name, which equals $what.'),
          reason: name,
        );
      }
    });
  });

  test('every slot always has a value', () {
    final profile = EffectiveProfile.compose([acme]);
    expect(profile.slots.keys, containsAll(Slot.values));
    expect(profile.vocabulary.frontmatterKeys, isEmpty);
    expect(profile.vocabulary.tags, isEmpty);
    expect(profile.vocabulary.actors, isEmpty);
  });
}
