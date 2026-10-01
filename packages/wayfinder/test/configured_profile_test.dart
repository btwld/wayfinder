import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/generated/installed_profiles.g.dart';
import 'package:wayfinder/src/profile_release.dart' show standardTypes;
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('the generated installed Profile files are current', () async {
    for (final (name, embedded) in [
      ('wayfinder-profile', installedProfileManifests),
      ('wayfinder-rules', installedRuleCatalogs),
    ]) {
      final files = [
        File('../../profile/$name.json'),
        ...Directory('../../profile/versions')
            .listSync()
            .whereType<File>()
            .where((file) => p.basename(file.path).startsWith('$name-')),
      ];
      final keys = <(String, String)>{};
      for (final file in files) {
        final text = await file.readAsString();
        final json = jsonDecode(text) as Map<String, Object?>;
        final source = json['profile'] is Map<String, Object?>
            ? json['profile'] as Map<String, Object?>
            : json;
        final key = (source['id'] as String, source['release'] as String);
        keys.add(key);
        expect(
          embedded[key],
          text,
          reason:
              '${file.path} is not embedded; run '
              'dart run tool/generate_installed_profiles.dart',
        );
      }
      expect(embedded.keys.toSet(), keys, reason: name);
    }
    expect(externalStandardTypes.length, 12);
    expect(standardTypes.length, 14);
  });
  late Directory project;
  late Directory bundle;

  Future<ProfileValidationResult> validateBundle(
    String path, {
    String? configPath,
  }) async {
    Map<String, WayfinderProfileBinding>? resolved;
    final file = File(configPath ?? p.join(project.path, 'wayfinder.json'));
    if (await file.exists()) {
      try {
        final config = WayfinderProjectConfig.parse(await file.readAsString());
        resolved = {
          for (final entry in config.profiles.entries)
            entry.key: WayfinderProfileBinding(
              id: entry.key,
              implementsId: builtinProfileId,
              release: externalProfileRelease,
              types: entry.value.types,
              tags: entry.value.tags,
              actors: entry.value.actors,
              source: entry.value.source,
              appliesTo: entry.value.appliesTo,
            ),
        };
      } on WayfinderConfigException {
        // Let the validator report malformed project configuration.
      }
    }
    return const ProfileValidator().validate(
      path,
      configPath: configPath,
      resolvedProfiles: resolved,
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

  test('does not resolve Profile sources when independent OKF fails', () async {
    final sample = File(p.join(bundle.path, 'sample.md'));
    await sample.writeAsString(
      (await sample.readAsString()).replaceFirst('type: Guide\n', ''),
    );
    var resolved = false;
    final result = await const ProfileValidator().validate(
      bundle.path,
      resolveSources: () async {
        resolved = true;
        throw StateError('Profile source resolution must not run');
      },
    );
    expect(result.okfState, OkfState.fail);
    expect(result.profileState, ProfileState.blockedByOkf);
    expect(resolved, isFalse);
  });

  test('configured type advisory identifies the configuration file', () async {
    final config = _config();
    final profile =
        (config['profiles'] as Map<String, Object?>)['bitwild_profile']!
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
    expect(
      result.findings
          .where(
            (finding) =>
                finding.id == 'concepta-profile/configured-type-extension',
          )
          .map((finding) => finding.path),
      [customConfig.path],
    );
  });

  test('rejects the unpublished installed-binding version 1 shape', () {
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({
          'version': 1,
          'profiles': {
            'main': {'implements': 'bitwild_profile/2026.3'},
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
        contains('concepta-profile/okf-release-binding'),
      );
    },
  );

  test('OKF Attested Computation is available without a custom type', () async {
    final index = File(p.join(bundle.path, 'index.md'));
    await index.writeAsString('''${await index.readAsString()}
# Attested Computation

* [Computation](computation.md) - A synthetic checkable computation.
''');
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
          'bitwild_profile': {
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
    final profile = config.profiles['bitwild_profile']!;
    expect(profile.source!.path, 'profile');
    expect(profile.source!.ref, 'v2026.3');
    expect(profile.appliesTo, ['knowledge', 'captures-bundle']);
  });

  test('schema and parser agree on safe relative paths', () async {
    final schema =
        jsonDecode(
              await File(
                '../../docs/schemas/wayfinder.schema.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final definitions = schema[r'$defs'] as Map<String, dynamic>;
    final source = definitions['profileSource'] as Map<String, dynamic>;
    final sourceProperties = source['properties'] as Map<String, dynamic>;
    final sourcePath = sourceProperties['path'] as Map<String, dynamic>;
    final direct = definitions['directProfile'] as Map<String, dynamic>;
    final directProperties = direct['properties'] as Map<String, dynamic>;
    final applies = directProperties['applies_to'] as Map<String, dynamic>;
    final item = applies['items'] as Map<String, dynamic>;
    expect(item['pattern'], sourcePath['pattern']);
    final pattern = RegExp(sourcePath['pattern'] as String);
    for (final path in ['profile', './knowledge', 'area/knowledge']) {
      expect(pattern.hasMatch(path), isTrue, reason: path);
    }
    for (final path in [
      '/tmp/knowledge',
      '../knowledge',
      'area/../knowledge',
      'knowledge\\secret',
      '.',
      'C:/knowledge',
      'C:knowledge',
      'knowledge\nsecret',
    ]) {
      expect(pattern.hasMatch(path), isFalse, reason: path);
    }
  });

  test('rejects direct Profile path overlap and unknown inheritance', () {
    final base = {
      'version': 1,
      'profiles': {
        'client': {
          'source': {
            'git': 'https://example.test/profile.git',
            'ref': 'main',
            'path': 'profile',
          },
          'applies_to': ['./knowledge'],
          'extends': 'missing',
        },
      },
    };
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(base)),
      throwsA(isA<WayfinderConfigException>()),
    );
    final overlapping = {
      'version': 1,
      'profiles': {
        'one': {
          'source': {
            'git': 'https://example.test/one.git',
            'ref': 'main',
            'path': 'profile',
          },
          'applies_to': ['./knowledge'],
        },
        'two': {
          'source': {
            'git': 'https://example.test/two.git',
            'ref': 'main',
            'path': 'profile',
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

  test('direct parents can be source-only and inheritance cycles fail', () {
    final config = {
      'version': 1,
      'profiles': {
        'bitwild_profile': {
          'source': {
            'git': 'https://example.test/base.git',
            'ref': 'main',
            'path': 'profile',
          },
          'applies_to': <String>[],
        },
        'client_profile': {
          'source': {
            'git': 'https://example.test/child.git',
            'ref': 'main',
            'path': 'profile',
          },
          'extends': 'bitwild_profile',
          'applies_to': ['./knowledge'],
        },
      },
    };
    expect(WayfinderProjectConfig.parse(jsonEncode(config)).bundles.length, 1);
    final profiles = config['profiles']! as Map<String, Object?>;
    final child = profiles['client_profile']! as Map<String, Object?>;
    child.remove('extends');
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(config)),
      throwsA(isA<WayfinderConfigException>()),
    );
    child['extends'] = 'bitwild_profile';
    profiles['other_profile'] = {
      'source': {
        'git': 'https://example.test/other.git',
        'ref': 'main',
        'path': 'profile',
      },
      'extends': 'client_profile',
      'applies_to': <String>[],
    };
    child['extends'] = 'other_profile';
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(config)),
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
          'path': 'profile',
        },
        'applies_to': ['./knowledge'],
      };
      WayfinderProjectConfig parse() => WayfinderProjectConfig.parse(
        jsonEncode({
          'version': 1,
          'profiles': {'bitwild_profile': profile},
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
        (profile['source']! as Map<String, Object?>)['path'] = 'profile';
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
        parse().profiles['bitwild_profile']!.source!.git,
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
          'concepta-profile/used-type-registered',
          'concepta-profile/configured-tag-undeclared',
          'concepta-profile/configured-tag-duplicate',
          'concepta-profile/used-actor-registered',
        ]),
      );
    },
  );

  test('orders configured index groups by Profile standard order', () async {
    final sample = File(p.join(bundle.path, 'sample.md'));
    await sample.writeAsString(
      (await sample.readAsString()).replaceFirst(
        'type: Guide',
        'type: Request',
      ),
    );
    await File(p.join(bundle.path, 'decision.md')).writeAsString(
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
    await File(p.join(bundle.path, 'index.md')).writeAsString(
      '''
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)

# Request

* [Sample](sample.md) - A sample guide.

# Decision

* [Decision](decision.md) - A sample decision.
'''
          .trimLeft(),
    );
    final result = await validateBundle(bundle.path);
    expect(result.profileState, ProfileState.pass);
  });

  test('rejects unknown fields and duplicate or colliding definitions', () {
    final valid = _config();
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({...valid, 'surprise': true}),
      ),
      throwsA(isA<WayfinderConfigException>()),
    );
    final binding =
        (valid['profiles'] as Map<String, Object?>)['bitwild_profile']!
            as Map<String, Object?>;
    binding['types'] = [
      {'name': 'Guide', 'description': 'Collision'},
    ];
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(valid)),
      throwsA(isA<WayfinderConfigException>()),
    );
    binding.remove('types');
    binding['tags'] = [
      {'name': 'governance', 'description': 'Topic'},
      {'name': 'governance', 'description': 'Duplicate'},
    ];
    expect(
      () => WayfinderProjectConfig.parse(jsonEncode(valid)),
      throwsA(isA<WayfinderConfigException>()),
    );
  });

  test('rejects explicit nulls for optional fields', () {
    expect(
      () => WayfinderProjectConfig.parse(
        jsonEncode({..._config(), 'default_bundle': null}),
      ),
      throwsA(isA<WayfinderConfigException>()),
    );
    for (final key in ['types', 'tags', 'actors']) {
      final config = jsonDecode(jsonEncode(_config())) as Map<String, dynamic>;
      final binding =
          (config['profiles'] as Map<String, dynamic>)['bitwild_profile']!
              as Map<String, dynamic>;
      binding[key] = null;
      expect(
        () => WayfinderProjectConfig.parse(jsonEncode(config)),
        throwsA(isA<WayfinderConfigException>()),
      );
    }
    final config = jsonDecode(jsonEncode(_config())) as Map<String, dynamic>;
    final binding =
        (config['profiles'] as Map<String, dynamic>)['bitwild_profile']!
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
    ((config['profiles'] as Map<String, Object?>)['bitwild_profile']!
        as Map<String, Object?>)['applies_to'] = [
      'knowledge',
      'escape',
    ];
    await _writeConfig(project, config);
    final result = await validateBundle(bundle.path);
    expect(result.okfState, OkfState.pass);
    expect(result.profileState, ProfileState.unsupported);
    expect(result.findings.single.message, contains('outside the project'));
  });

  test('discovers project configuration for a nested bundle path', () async {
    final nested = await Directory(p.join(project.path, 'nested')).create();
    final moved = await bundle.rename(p.join(nested.path, 'knowledge'));
    final config = _config();
    ((config['profiles'] as Map<String, Object?>)['bitwild_profile']!
        as Map<String, Object?>)['applies_to'] = [
      'nested/knowledge',
    ];
    await _writeConfig(project, config);
    final result = await validateBundle(moved.path);
    expect(result.profileState, ProfileState.pass);
    expect(result.profileRelease, '2026.3');
  });

  test('keeps an unlisted legacy bundle on its declared release', () async {
    final legacy = await copyFixture('conformant');
    final moved = await legacy.rename(p.join(project.path, 'legacy'));
    final result = await validateBundle(moved.path);
    expect(result.profileRelease, '2026.2');
    expect(result.profileState, ProfileState.pass);
  });

  test('reports an unlisted nonlegacy bundle as a binding error', () async {
    final other = await Directory(p.join(project.path, 'other')).create();
    await _writeBundle(other);
    final result = await validateBundle(other.path);
    expect(result.profileState, ProfileState.unsupported);
    expect(result.findings.single.message, contains('not listed'));
  });

  test('rejects a 2026.3 selector in legacy profile.md', () async {
    final legacy = await copyFixture('conformant');
    addTearDown(() => legacy.delete(recursive: true));
    final declaration = File(p.join(legacy.path, 'profile.md'));
    await declaration.writeAsString(
      (await declaration.readAsString()).replaceAll('2026.2', '2026.3'),
    );
    final result = await validateBundle(legacy.path);
    expect(result.profileState, ProfileState.unsupported);
  });

  test('reserves nested registry names only under legacy 2026.2', () async {
    const concept = '''
---
type: Guide
title: Area types
description: An ordinary concept named like a legacy registry.
status: stable
---

# Area types
''';
    Future<List<String?>> reservedNameFindings(
      Directory root,
      String release,
    ) async {
      final area = await Directory(p.join(root.path, 'area')).create();
      await File(p.join(area.path, 'types.md')).writeAsString(concept);
      final result = await validateBundle(root.path);
      expect(result.okfState, OkfState.pass);
      expect(result.profileRelease, release);
      return result.findings
          .where(
            (finding) => finding.id == 'concepta-profile/root-structure-files',
          )
          .map((finding) => finding.path)
          .toList();
    }

    expect(await reservedNameFindings(bundle, '2026.3'), isEmpty);
    final legacy = await copyFixture('conformant');
    addTearDown(() => legacy.delete(recursive: true));
    expect(await reservedNameFindings(legacy, '2026.2'), ['area/types.md']);
  });

  test(
    'migrates a legacy root without reinterpreting its old release',
    () async {
      await File(p.join(project.path, 'wayfinder.json')).delete();
      await bundle.delete(recursive: true);
      final legacy = await copyFixture('conformant');
      bundle = await legacy.rename(p.join(project.path, 'knowledge'));
      final old = await validateBundle(bundle.path);
      expect(old.profileRelease, '2026.2');
      expect(old.profileState, ProfileState.pass);

      await _writeConfig(project);
      final halfway = await validateBundle(bundle.path);
      expect(halfway.profileState, ProfileState.fail);
      expect(
        halfway.findings.map((finding) => finding.id),
        contains('concepta-profile/configuration-legacy-registry'),
      );

      for (final name in ['profile.md', 'types.md', 'actors.md']) {
        await File(p.join(bundle.path, name)).delete();
      }
      await File(p.join(bundle.path, 'index.md')).writeAsString(
        '''
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
'''
            .trimLeft(),
      );
      final migrated = await validateBundle(bundle.path);
      expect(migrated.profileRelease, '2026.3');
      expect(migrated.profileState, ProfileState.pass);
    },
  );
}

Map<String, Object?> _config() => {
  'version': 1,
  'profiles': {
    'bitwild_profile': {
      'source': {
        'git': 'https://example.test/wayfinder.git',
        'ref': 'v2026.3',
        'path': 'profile',
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

# Bundle

* [Knowledge Log](log.md)

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
