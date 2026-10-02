import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test(
    'the engine embeds its schemas and okf version, and no Profile',
    () async {
      final source = await File(
        'lib/src/generated/published_schemas.g.dart',
      ).readAsString();
      expect(
        RegExp(
          r'^const String (\w+)',
          multiLine: true,
        ).allMatches(source).map((match) => match[1]),
        [
          'wayfinderConfigurationSchema',
          'wayfinderProfileSchema',
          'okfPackageVersion',
        ],
      );
      expect(source, isNot(contains('bitwild')));
    },
  );

  late Directory project;
  late Directory bundle;

  Future<ProfileValidationResult> validateBundle(
    String path, {
    String? configPath,
    bool fix = false,
  }) async {
    return const ProfileValidator().validate(
      path,
      await selectFixture(path, configPath: configPath),
      fix: fix,
    );
  }

  setUp(() async {
    project = await Directory.systemTemp.createTemp('wayfinder-config-');
    bundle = await Directory(p.join(project.path, 'knowledge')).create();
    await _writeBundle(bundle);
    await _writeConfig(project);
  });

  tearDown(() async => project.delete(recursive: true));

  test('validates an external binding with declared tags and actors', () async {
    final result = await validateBundle(bundle.path);
    expect(result.profileRelease, '2026.3');
    expect(result.profileState, ProfileState.pass);
    expect(result.exitCode, 0);
  });

  test('reports why no Profile was selected, but runs no Profile rule, when '
      'independent OKF fails', () async {
    final sample = File(p.join(bundle.path, 'sample.md'));
    await sample.writeAsString(
      (await sample.readAsString()).replaceFirst('type: Guide\n', ''),
    );
    final result = await const ProfileValidator().validate(
      bundle.path,
      UnselectedProfile([
        const EngineDiagnostic(
          DiagnosticCode.profileUnresolved,
          'Run wayfinder get.',
        ),
      ]),
    );
    expect(result.okfState, OkfState.fail);
    expect(result.profileState, ProfileState.blockedByOkf);
    expect(result.findings, isEmpty);
    expect(result.diagnostics.map((d) => d.code), [
      DiagnosticCode.profileUnresolved,
    ]);
    expect(result.gate, GateState.fail);
  });

  test('a project type note identifies the configuration file', () async {
    final config = _config();
    final profile =
        (config['profiles'] as Map<String, Object?>)['bitwild-profile']!
            as Map<String, Object?>;
    profile['types'] = [
      {'name': 'Project Note', 'description': 'A local project note.'},
    ];
    await _writeConfig(project, config);
    final customConfig = File(p.join(project.path, 'settings.json'));
    await File(
      p.join(project.path, 'wayfinder.json'),
    ).rename(customConfig.path);
    final result = await validateBundle(
      bundle.path,
      configPath: customConfig.path,
    );
    expect(result.profileState, ProfileState.pass);
    final note = result.diagnostics.single;
    expect(note.code, DiagnosticCode.projectType);
    expect(note.location, isA<ProjectFileLocation>());
    expect(note.location!.path, customConfig.path);
    expect(result.gate, GateState.pass);
  });

  test('a bundle whose only reports are notes passes with exit 0', () async {
    final result = await validateFixture(fixture('configured-extensions'));
    expect(result.findings, isEmpty);
    expect(result.diagnostics.map((d) => d.id), ['wayfinder/project-type']);
    expect(result.profileState, ProfileState.pass);
    expect(result.gate, GateState.pass);
    expect(result.exitCode, 0);
    final text = result.toTextLines().toList();
    expect(text.sublist(text.indexOf('Diagnostics:')), [
      'Diagnostics:',
      'test/fixtures/configured-extensions/wayfinder.json: '
          'note wayfinder/project-type: '
          'Configured project type Runbook is available to this bundle.',
      'Gate: PASS',
    ]);
  });

  test('prints no summary block when nothing was summarized', () async {
    final result = await validateFixture(fixture('configured-project'));
    expect(result.summary, isEmpty);
    expect(result.toJson()['profile'], containsPair('summary', isEmpty));
    expect(result.toTextLines(), isNot(contains('Summary:')));
  });

  test('rejects the unpublished installed-binding version 1 shape', () {
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({
          'version': 1,
          'profiles': {
            'main': {'implements': 'bitwild-profile/2026.3'},
          },
          'bundles': [
            {'id': 'knowledge', 'path': 'knowledge', 'profile': 'main'},
          ],
        }),
      ),
      throwsA(isA<WayfinderConfigException>()),
    );
  });

  test(
    '2026.3 requires the root OKF 0.2 marker independently of OKF',
    () async {
      final index = File(p.join(bundle.path, 'index.md'));
      final original = await index.readAsString();
      await index.writeAsString(
        original.replaceFirst('---\nokf_version: "0.2"\n---\n', ''),
      );
      final missing = await validateBundle(bundle.path);
      expect(missing.okfState, OkfState.pass);
      expect(missing.profileState, ProfileState.fail);
      expect(
        missing.findings.map((finding) => finding.path),
        contains('index.md'),
      );

      await index.writeAsString(
        original.replaceFirst('okf_version: "0.2"', 'okf_version: "0.3"'),
      );
      final wrong = await validateBundle(bundle.path);
      expect(wrong.okfState, OkfState.pass);
      expect(wrong.profileState, ProfileState.fail);
      expect(
        wrong.findings.map((finding) => finding.id),
        contains('bitwild-profile/okf-release-binding'),
      );
    },
  );

  test('OKF Attested Computation is available without a custom type', () async {
    await File(p.join(bundle.path, 'index.md')).writeAsString(
      '''
---
okf_version: "0.2"
---

# Attested Computation

* [Computation](computation.md) - A synthetic checkable computation.

# Guide

* [Sample](sample.md) - A sample guide.
'''
          .trimLeft(),
    );
    await File(p.join(bundle.path, 'computation.md')).writeAsString(
      '''
---
type: Attested Computation
title: Computation
description: A synthetic checkable computation.
status: stable
runtime: python
parameters:
  - {name: value, type: integer, required: true}
executor:
  resource: https://example.test/run
  receipt: [result]
attester:
  resource: https://example.test/check
---

# Computation

```python
result = value + 1
```
'''
          .trimLeft(),
    );
    final result = await validateBundle(bundle.path);
    expect(result.okfState, OkfState.pass);
    expect(result.profileState, ProfileState.pass);
  });

  test('parses direct Git Profile sources and applies_to paths', () {
    final config = WayfinderProjectConfig.parse(
      jsonEncode({
        'version': 1,
        'profiles': {
          'bitwild-profile': {
            'source': {
              'git': 'https://example.test/profile.git',
              'ref': 'v2026.3',
              'path': './profile',
            },
            'applies_to': ['./knowledge', './captures-bundle'],
          },
        },
      }),
    );
    expect(config.bundles.map((bundle) => bundle.path), [
      'knowledge',
      'captures-bundle',
    ]);
    final profile = config.profiles[ProfileId.parse('bitwild-profile')]!;
    expect(profile.source.path, 'profile');
    expect(profile.source.ref, 'v2026.3');
    expect(profile.appliesTo, ['knowledge', 'captures-bundle']);
  });

  test('reports a schema violation at its instance pointer', () {
    String message(void Function(Map<String, dynamic> profile) edit) {
      final config = jsonDecode(jsonEncode(_config())) as Map<String, dynamic>;
      edit(
        (config['profiles'] as Map<String, dynamic>)['bitwild-profile']
            as Map<String, dynamic>,
      );
      try {
        WayfinderProjectConfig.parse(jsonEncode(config));
      } on WayfinderConfigException catch (error) {
        return error.message;
      }
      fail('parsed');
    }

    const at = 'wayfinder.json is invalid at /profiles/bitwild-profile';
    expect(
      message((profile) => profile['rules'] = {'allow_anything': true}),
      '$at: has unknown property rules.',
    );
    expect(
      message((profile) => profile.remove('source')),
      '$at: is missing required property source.',
    );
    expect(
      message(
        (profile) =>
            (profile['actors'] as Map<String, dynamic>)['process:test'] = {
              'name': 'Test process',
              'side': 'partner',
            },
      ),
      '$at/actors/process:test/side: '
      'must be one of client, internal, vendor, tool, unknown.',
    );
    expect(
      message(
        (profile) => profile['types'] = [
          {'name': '', 'description': 'Empty'},
        ],
      ),
      '$at/types/0/name: must be a non-empty string.',
    );
    expect(
      message(
        (profile) => profile['tags'] = [
          {'name': ' ', 'description': 'Blank'},
        ],
      ),
      '$at/tags/0/name: must be a non-empty string.',
    );
    expect(
      message((profile) => profile['applies_to'] = ['../knowledge']),
      '$at/applies_to/0: must be a relative path without parent traversal.',
    );
    expect(
      message(
        (profile) => (profile['source'] as Map<String, dynamic>)['ref'] = '-x',
      ),
      '$at/source/ref: must be a valid Git ref, with no leading hyphen, '
      'no .. and no whitespace or control characters.',
    );
    expect(
      message((profile) => profile['extends'] = 'bitwild-profile'),
      '$at: has unknown property extends.',
    );
    expect(
      message((profile) => profile['applies_to'] = <String>[]),
      '$at/applies_to: must not be empty.',
    );
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({'version': 1, 'profiles': <String, Object?>{}}),
      ),
      throwsA(
        isA<WayfinderConfigException>().having(
          (error) => error.message,
          'message',
          'wayfinder.json is invalid at /profiles: must not be empty.',
        ),
      ),
    );
  });

  test('rejects overlapping bundle paths across Profiles', () {
    final overlapping = {
      'version': 1,
      'profiles': {
        'one': {
          'source': {
            'git': 'https://example.test/one.git',
            'ref': 'main',
            'path': 'profiles/bitwild',
          },
          'applies_to': ['./knowledge'],
        },
        'two': {
          'source': {
            'git': 'https://example.test/two.git',
            'ref': 'main',
            'path': 'profiles/bitwild',
          },
          'applies_to': ['./knowledge/references'],
        },
      },
    };
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(overlapping)),
      throwsA(isA<WayfinderConfigException>()),
    );
  });

  test(
    'direct Profile rejects unsafe paths, credentials and rule overrides',
    () {
      final profile = <String, Object?>{
        'source': <String, Object?>{
          'git': 'https://example.test/base.git',
          'ref': 'main',
          'path': 'profiles/bitwild',
        },
        'applies_to': ['./knowledge'],
      };
      WayfinderProjectConfig parse() => WayfinderProjectConfig.parse(
        jsonEncode({
          'version': 1,
          'profiles': {'bitwild-profile': profile},
        }),
      );
      for (final path in [
        '/tmp/knowledge',
        '../knowledge',
        'knowledge\\secret',
        '.',
        'C:/knowledge',
        'C:knowledge',
        'knowledge\nsecret',
      ]) {
        profile['applies_to'] = [path];
        expect(() => parse(), throwsA(isA<WayfinderConfigException>()));
        profile['applies_to'] = ['./knowledge'];
        (profile['source']! as Map<String, Object?>)['path'] = path;
        expect(() => parse(), throwsA(isA<WayfinderConfigException>()));
        (profile['source']! as Map<String, Object?>)['path'] =
            'profiles/bitwild';
      }
      profile['applies_to'] = ['./knowledge'];
      (profile['source']! as Map<String, Object?>)['git'] =
          'https://user:secret@example.test/base.git';
      expect(() => parse(), throwsA(isA<WayfinderConfigException>()));
      (profile['source']! as Map<String, Object?>)['git'] =
          'ssh://git:secret@example.test/base.git';
      expect(() => parse(), throwsA(isA<WayfinderConfigException>()));
      (profile['source']! as Map<String, Object?>)['git'] =
          'ssh://git@example.test/base.git';
      expect(
        parse().profiles[ProfileId.parse('bitwild-profile')]!.source.git,
        'ssh://git@example.test/base.git',
      );
      (profile['source']! as Map<String, Object?>)['git'] =
          'https://example.test/base.git';
      (profile['source']! as Map<String, Object?>)['git'] = 'C:relative';
      expect(() => parse(), throwsA(isA<WayfinderConfigException>()));
      (profile['source']! as Map<String, Object?>)['git'] =
          'https://example.test/base.git';
      profile['rules'] = {'allow_anything': true};
      expect(() => parse(), throwsA(isA<WayfinderConfigException>()));
    },
  );

  test(
    'checks tag, type and actor references in the selected bundle',
    () async {
      final concept = File(p.join(bundle.path, 'sample.md'));
      var source = await concept.readAsString();
      source = source.replaceFirst('type: Guide', 'type: Mystery');
      source = source.replaceFirst(
        'tags: [governance]',
        'tags: [unknown, unknown]',
      );
      source = source.replaceFirst('process:test', 'process:unlisted');
      await concept.writeAsString(source);
      final result = await validateBundle(bundle.path);
      expect(result.profileState, ProfileState.fail);
      expect(
        result.findings.map((finding) => finding.id),
        containsAll([
          'bitwild-profile/used-type-registered',
          'bitwild-profile/configured-tag-undeclared',
          'bitwild-profile/configured-tag-duplicate',
          'bitwild-profile/used-actor-registered',
        ]),
      );
    },
  );

  test('2026.3 indexes are exactly the okf generator output', () async {
    final sample = File(p.join(bundle.path, 'sample.md'));
    await sample.writeAsString(
      (await sample.readAsString()).replaceFirst(
        'type: Guide',
        'type: Request',
      ),
    );
    final area = await Directory(p.join(bundle.path, 'area')).create();
    await File(p.join(area.path, 'decision.md')).writeAsString(
      '''
---
type: Decision
title: Decision
description: A sample decision.
status: stable
---

# Decision
'''
          .trimLeft(),
    );
    final index = File(p.join(bundle.path, 'index.md'));
    await index.writeAsString(
      '''
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)

# Request

* [Sample](sample.md) - A sample guide.

# Directories

* [area](area/)
'''
          .trimLeft(),
    );

    final stale = await validateBundle(bundle.path);
    expect(stale.profileState, ProfileState.fail);
    expect(
      stale.findings
          .where((finding) => finding.id == 'bitwild-profile/index-current')
          .map((finding) => finding.path),
      ['area/index.md', 'index.md'],
    );

    final fixed = await validateBundle(bundle.path, fix: true);
    expect(fixed.fixed, ['area/index.md', 'index.md']);
    expect(fixed.profileState, ProfileState.pass);
    expect(
      await index.readAsString(),
      '''
---
okf_version: "0.2"
---

# Request

* [Sample](sample.md) - A sample guide.

# Subdirectories

* [area](area/index.md) - A sample decision.
'''
          .trimLeft(),
    );

    final again = await validateBundle(bundle.path, fix: true);
    expect(again.fixed, isEmpty);
    expect(again.profileState, ProfileState.pass);
  });

  test(
    '--fix never writes an unconfigured bundle or one OKF rejects',
    () async {
      final unconfigured = await copyFixture('unconfigured');
      addTearDown(() => unconfigured.delete(recursive: true));
      final before = await _snapshot(unconfigured);
      final unselected = await const ProfileValidator().validate(
        unconfigured.path,
        await selectFixture(unconfigured.path),
        fix: true,
      );
      expect(unselected.profileState, ProfileState.notAssessed);
      expect(unselected.fixed, isNull);
      expect(unselected.diagnostics.map((d) => d.code), [
        DiagnosticCode.configMissing,
        DiagnosticCode.fixNotApplied,
      ]);
      expect(await _snapshot(unconfigured), before);

      await File(p.join(bundle.path, 'index.md')).delete();
      final sample = File(p.join(bundle.path, 'sample.md'));
      await sample.writeAsString(
        (await sample.readAsString()).replaceFirst('type: Guide\n', ''),
      );
      final blocked = await validateBundle(bundle.path, fix: true);
      expect(blocked.profileState, ProfileState.blockedByOkf);
      expect(blocked.fixed, isNull);
      expect(blocked.diagnostics.map((d) => d.code), [
        DiagnosticCode.fixNotApplied,
      ]);
      expect(await File(p.join(bundle.path, 'index.md')).exists(), isFalse);
    },
  );

  test('rejects unknown fields and duplicate definitions', () {
    final valid = _config();
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({...valid, 'surprise': true}),
      ),
      throwsA(isA<WayfinderConfigException>()),
    );
    final binding =
        (valid['profiles'] as Map<String, Object?>)['bitwild-profile']!
            as Map<String, Object?>;
    binding['tags'] = [
      {'name': 'governance', 'description': 'Topic'},
      {'name': 'governance', 'description': 'Duplicate'},
    ];
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(valid)),
      throwsA(
        isA<WayfinderConfigException>().having(
          (error) => error.message,
          'message',
          'Profile bitwild-profile declares a duplicate tag governance.',
        ),
      ),
    );
    binding.remove('tags');
    binding['relationships'] = [
      {'name': 'runs-after', 'description': 'Project name'},
      {'name': 'runs-after', 'description': 'Duplicate'},
    ];
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(valid)),
      throwsA(
        isA<WayfinderConfigException>().having(
          (error) => error.message,
          'message',
          'Profile bitwild-profile declares a duplicate relationship '
              'runs-after.',
        ),
      ),
    );
    binding['relationships'] = [
      {'name': 'runs-after', 'description': 'Project name'},
    ];
    expect(
      WayfinderProjectConfig.parse(jsonEncode(valid))
          .profiles[ProfileId.parse('bitwild-profile')]!
          .project
          .relationships
          .map((definition) => definition.name),
      ['runs-after'],
    );
  });

  test('a declaration that collides with the Profile chain is reported when '
      'the chain is composed, not by the configuration', () async {
    for (final (field, name, collision) in [
      ('tags', 'draft', 'tag draft, which equals an OKF status value'),
      (
        'tags',
        'human-reviewed',
        'tag human-reviewed, which equals an OKF trust tier',
      ),
      (
        'tags',
        'depends-on',
        'tag depends-on, which equals a declared relationship name',
      ),
      ('types', 'incident', 'tag incident, which equals a declared type name'),
      (
        'relationships',
        'incident',
        'tag incident, which equals a declared relationship name',
      ),
      (
        'types',
        'Guide',
        'type Guide, which Profile bitwild-profile already declares',
      ),
      (
        'relationships',
        'depends-on',
        'relationship depends-on, which Profile bitwild-profile already '
            'declares',
      ),
    ]) {
      final config = _config();
      final binding =
          (config['profiles'] as Map<String, Object?>)['bitwild-profile']!
              as Map<String, Object?>;
      binding['tags'] = [
        {'name': 'incident', 'description': 'An incident topic'},
      ];
      final definition = {'name': name, 'description': 'Collides'};
      binding.update(
        field,
        (list) => [...list as List<Object?>, definition],
        ifAbsent: () => [definition],
      );
      await _writeConfig(project, config);
      final result = await validateBundle(bundle.path);
      expect(result.profileState, ProfileState.notAssessed, reason: name);
      expect(result.diagnostics.single.code, DiagnosticCode.profileComposition);
      expect(
        result.diagnostics.single.message,
        'Profile bitwild-profile: The project declares $collision.',
        reason: '$field $name',
      );
      expect(result.gate, GateState.incomplete);
    }
  });

  test('rejects explicit nulls for optional fields', () {
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({..._config(), 'default_bundle': null}),
      ),
      throwsA(isA<WayfinderConfigException>()),
    );
    for (final key in ['types', 'tags', 'relationships', 'actors']) {
      final config = jsonDecode(jsonEncode(_config())) as Map<String, dynamic>;
      final binding =
          (config['profiles'] as Map<String, dynamic>)['bitwild-profile']!
              as Map<String, dynamic>;
      binding[key] = null;
      expect(
        () => WayfinderProjectConfig.parse(jsonEncode(config)),
        throwsA(isA<WayfinderConfigException>()),
      );
    }
    final config = jsonDecode(jsonEncode(_config())) as Map<String, dynamic>;
    final binding =
        (config['profiles'] as Map<String, dynamic>)['bitwild-profile']!
            as Map<String, dynamic>;
    final actor =
        (binding['actors'] as Map<String, dynamic>)['process:test']!
            as Map<String, dynamic>;
    actor['side'] = null;
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(config)),
      throwsA(isA<WayfinderConfigException>()),
    );
  });

  test('rejects duplicate JSON keys before later values overwrite them', () {
    final source = jsonEncode(_config());
    final duplicateActor = source.replaceFirst(
      '"process:test":',
      '"process:test":{"name":"First"},"process:test":',
    );
    expect(
      () => WayfinderProjectConfig.parse(duplicateActor),
      throwsA(isA<WayfinderConfigException>()),
    );
    final escapedDuplicate = source.replaceFirst(
      '"process:test":',
      '"process:test":{"name":"First"},"process\\u003atest":',
    );
    expect(
      () => WayfinderProjectConfig.parse(escapedDuplicate),
      throwsA(isA<WayfinderConfigException>()),
    );
  });

  test('rejects an escaping configured path without losing OKF', () async {
    if (Platform.isWindows) return;
    final outside = await Directory.systemTemp.createTemp('wayfinder-outside-');
    addTearDown(() => outside.delete(recursive: true));
    await Link(p.join(project.path, 'escape')).create(outside.path);
    final config = _config();
    ((config['profiles'] as Map<String, Object?>)['bitwild-profile']!
        as Map<String, Object?>)['applies_to'] = [
      'knowledge',
      'escape',
    ];
    await _writeConfig(project, config);
    final result = await validateBundle(bundle.path);
    expect(result.okfState, OkfState.pass);
    expect(result.profileState, ProfileState.notAssessed);
    expect(result.diagnostics.single.code, DiagnosticCode.configInvalid);
    expect(result.diagnostics.single.message, contains('outside the project'));
  });

  test('discovers project configuration for a nested bundle path', () async {
    final nested = await Directory(p.join(project.path, 'nested')).create();
    final moved = await bundle.rename(p.join(nested.path, 'knowledge'));
    final config = _config();
    ((config['profiles'] as Map<String, Object?>)['bitwild-profile']!
        as Map<String, Object?>)['applies_to'] = [
      'nested/knowledge',
    ];
    await _writeConfig(project, config);
    final result = await validateBundle(moved.path);
    expect(result.profileState, ProfileState.pass);
    expect(result.profileRelease, '2026.3');
  });

  test('reports an unlisted bundle as a binding error, even with a 2026.2 '
      'declaration', () async {
    final other = await Directory(p.join(project.path, 'other')).create();
    await _writeBundle(other);
    for (final declared in [false, true]) {
      if (declared) await _writeRetiredRegistries(other);
      final result = await validateBundle(other.path);
      expect(
        result.profileState,
        ProfileState.notAssessed,
        reason: '$declared',
      );
      expect(result.diagnostics.single.code, DiagnosticCode.bundleUnbound);
      expect(result.diagnostics.single.message, contains('not listed'));
    }
  });

  test('a nested registry name is an ordinary concept', () async {
    final area = await Directory(p.join(bundle.path, 'area')).create();
    await File(p.join(area.path, 'types.md')).writeAsString('''
---
type: Guide
title: Area types
description: An ordinary concept named like a former registry.
status: stable
generated: {by: process:test, at: 2026-09-27T00:00:00Z}
---

# Area types
''');
    final result = await validateBundle(bundle.path, fix: true);
    expect(result.okfState, OkfState.pass);
    expect(result.profileState, ProfileState.pass);
  });

  test('a configured bundle must drop its 2026.2 registries', () async {
    await _writeRetiredRegistries(bundle);
    final halfway = await validateBundle(bundle.path);
    expect(halfway.profileState, ProfileState.fail);
    expect(
      halfway.findings
          .where(
            (finding) =>
                finding.id == 'bitwild-profile/configuration-legacy-registry',
          )
          .map((finding) => finding.path),
      ['actors.md', 'profile.md', 'types.md'],
    );

    for (final name in ['profile.md', 'types.md', 'actors.md']) {
      await File(p.join(bundle.path, name)).delete();
    }
    final migrated = await validateBundle(bundle.path);
    expect(migrated.profileRelease, '2026.3');
    expect(migrated.profileState, ProfileState.pass);
  });
}

Future<Map<String, List<int>>> _snapshot(Directory root) async => {
  await for (final entity in root.list(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: root.path): await entity.readAsBytes(),
};

Map<String, Object?> _config() => {
  'version': 1,
  'profiles': {
    'bitwild-profile': {
      'source': {
        'git': 'https://example.test/wayfinder.git',
        'ref': 'v2026.3',
        'path': 'profiles/bitwild',
      },
      'applies_to': ['knowledge'],
      'actors': {
        'process:test': {'name': 'Test process'},
      },
      'tags': [
        {'name': 'governance', 'description': 'Governance topic'},
      ],
    },
  },
};

Future<void> _writeConfig(Directory project, [Map<String, Object?>? config]) =>
    File(
      p.join(project.path, 'wayfinder.json'),
    ).writeAsString(jsonEncode(config ?? _config()));

Future<void> _writeBundle(Directory bundle) async {
  await File(p.join(bundle.path, 'index.md')).writeAsString(
    '''
---
okf_version: "0.2"
---

# Guide

* [Sample](sample.md) - A sample guide.
'''
        .trimLeft(),
  );
  await File(p.join(bundle.path, 'log.md')).writeAsString(
    '''
# Bundle Update Log

## 2026-09-27

* **Creation**: Created the sample bundle.
'''
        .trimLeft(),
  );
  await File(p.join(bundle.path, 'sample.md')).writeAsString(
    '''
---
type: Guide
title: Sample
description: A sample guide.
status: stable
tags: [governance]
generated: {by: process:test, at: 2026-09-27T00:00:00Z}
---

# Sample

A sample guide.
'''
        .trimLeft(),
  );
}

Future<void> _writeRetiredRegistries(Directory bundle) async {
  for (final (name, type) in [
    ('profile.md', 'Knowledge Profile'),
    ('types.md', 'Type Registry'),
    ('actors.md', 'Actor Registry'),
  ]) {
    await File(p.join(bundle.path, name)).writeAsString('''
---
type: $type
title: $type
description: A 2026.2 registry left in the bundle.
status: stable
---

# $type
''');
  }
}
