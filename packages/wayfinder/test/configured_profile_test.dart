import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/profile_release.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('installed manifest matches the built-in release vocabulary', () async {
    final manifest =
        jsonDecode(
              await File('../../profile/wayfinder-profile.json').readAsString(),
            )
            as Map<String, Object?>;
    expect(manifest['id'], builtinProfileId);
    expect(manifest['release'], externalProfileRelease);
    expect(manifest['implements'], {'id': 'okf', 'release': '0.2'});
    expect(
      (manifest['standard_types'] as List<Object?>)
          .map(
            (item) =>
                ((item as Map<String, Object?>)['name'], item['description']),
          )
          .toList(),
      externalStandardTypes,
    );
    expect(
      (manifest['tags'] as List<Object?>)
          .map(
            (item) =>
                ((item as Map<String, Object?>)['name'], item['description']),
          )
          .toList(),
      externalStandardTags,
    );
  });
  late Directory project;
  late Directory bundle;

  setUp(() async {
    project = await Directory.systemTemp.createTemp('wayfinder-config-');
    bundle = await Directory(p.join(project.path, 'knowledge')).create();
    await _writeBundle(bundle);
    await _writeConfig(project);
  });

  tearDown(() async => project.delete(recursive: true));

  test('validates an external binding with declared tags and actors', () async {
    final result = await const ProfileValidator().validate(bundle.path);
    expect(result.profileRelease, '2026.3');
    expect(result.profileState, ProfileState.pass);
    expect(result.exitCode, 0);
  });

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
      final result = await const ProfileValidator().validate(bundle.path);
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
    final result = await const ProfileValidator().validate(bundle.path);
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
        (valid['profiles'] as Map<String, Object?>)['main']!
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
          (config['profiles'] as Map<String, dynamic>)['main']!
              as Map<String, dynamic>;
      binding[key] = null;
      expect(
        () => WayfinderProjectConfig.parse(jsonEncode(config)),
        throwsA(isA<WayfinderConfigException>()),
      );
    }
    final config = jsonDecode(jsonEncode(_config())) as Map<String, dynamic>;
    final binding =
        (config['profiles'] as Map<String, dynamic>)['main']!
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

  test('rejects a configured bundle symlink escaping the project', () async {
    if (Platform.isWindows) return;
    final outside = await Directory.systemTemp.createTemp('wayfinder-outside-');
    addTearDown(() => outside.delete(recursive: true));
    await Link(p.join(project.path, 'escape')).create(outside.path);
    final config = _config();
    (config['bundles'] as List<Object?>).add({
      'id': 'escape',
      'path': 'escape',
      'profile': 'main',
    });
    await _writeConfig(project, config);
    final result = await const ProfileValidator().validate(bundle.path);
    expect(result.profileState, ProfileState.unsupported);
    expect(result.findings.single.message, contains('outside the project'));
  });

  test('discovers project configuration for a nested bundle path', () async {
    final nested = await Directory(p.join(project.path, 'nested')).create();
    final moved = await bundle.rename(p.join(nested.path, 'knowledge'));
    final config = _config();
    (config['bundles'] as List<Object?>).first = {
      'id': 'knowledge',
      'path': 'nested/knowledge',
      'profile': 'main',
    };
    await _writeConfig(project, config);
    final result = await const ProfileValidator().validate(moved.path);
    expect(result.profileState, ProfileState.pass);
    expect(result.profileRelease, '2026.3');
  });

  test('keeps an unlisted legacy bundle on its declared release', () async {
    final legacy = await copyFixture('conformant');
    final moved = await legacy.rename(p.join(project.path, 'legacy'));
    final result = await const ProfileValidator().validate(moved.path);
    expect(result.profileRelease, '2026.2');
    expect(result.profileState, ProfileState.pass);
  });

  test('reports an unlisted nonlegacy bundle as a binding error', () async {
    final other = await Directory(p.join(project.path, 'other')).create();
    await _writeBundle(other);
    final result = await const ProfileValidator().validate(other.path);
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
    final result = await const ProfileValidator().validate(legacy.path);
    expect(result.profileState, ProfileState.unsupported);
  });

  test(
    'migrates a legacy root without reinterpreting its old release',
    () async {
      await File(p.join(project.path, 'wayfinder.json')).delete();
      await bundle.delete(recursive: true);
      final legacy = await copyFixture('conformant');
      bundle = await legacy.rename(p.join(project.path, 'knowledge'));
      final old = await const ProfileValidator().validate(bundle.path);
      expect(old.profileRelease, '2026.2');
      expect(old.profileState, ProfileState.pass);

      await _writeConfig(project);
      final halfway = await const ProfileValidator().validate(bundle.path);
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
      final migrated = await const ProfileValidator().validate(bundle.path);
      expect(migrated.profileRelease, '2026.3');
      expect(migrated.profileState, ProfileState.pass);
    },
  );
}

Map<String, Object?> _config() => {
  'version': 1,
  'profiles': {
    'main': {
      'implements': 'bitwild_profile/2026.3',
      'actors': {
        'process:test': {'name': 'Test process'},
      },
      'tags': [
        {'name': 'governance', 'description': 'Governance topic'},
      ],
    },
  },
  'bundles': [
    {'id': 'knowledge', 'path': 'knowledge', 'profile': 'main'},
  ],
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
