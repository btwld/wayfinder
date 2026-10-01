import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/profile_resolver.dart';

void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late Directory data;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-profile-source-');
    source = await Directory(p.join(temp.path, 'source')).create();
    project = await Directory(p.join(temp.path, 'project')).create();
    await Directory(p.join(project.path, 'knowledge')).create();
    data = Directory(p.join(temp.path, 'data'));
    await _git(source.path, ['init', '-q']);
    await _git(source.path, ['config', 'user.email', 'test@example.test']);
    await _git(source.path, ['config', 'user.name', 'Wayfinder Test']);
    await Directory(p.join(source.path, 'profile')).create();
    await File(
      '../../profile/wayfinder-profile.json',
    ).copy(p.join(source.path, 'profile', 'wayfinder-profile.json'));
    await _git(source.path, ['add', '.']);
    await _git(source.path, ['commit', '-q', '-m', 'Profile']);
    await _git(source.path, ['tag', 'v2026.3']);
    await File(p.join(project.path, 'wayfinder.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'profiles': {
          'bitwild_profile': {
            'source': {'git': source.path, 'ref': 'v2026.3', 'path': 'profile'},
            'applies_to': ['./knowledge'],
          },
        },
      }),
    );
  });

  tearDown(() => temp.delete(recursive: true));

  Future<Map<String, dynamic>> config() async =>
      jsonDecode(
            await File(p.join(project.path, 'wayfinder.json')).readAsString(),
          )
          as Map<String, dynamic>;

  Future<void> saveConfig(Map<String, dynamic> value) => File(
    p.join(project.path, 'wayfinder.json'),
  ).writeAsString(jsonEncode(value));

  Future<String> lockCommit() async {
    final lock =
        jsonDecode(
              await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
            )
            as Map<String, dynamic>;
    return (lock['profiles']
            as Map<String, dynamic>)['bitwild_profile']['resolved_commit']
        as String;
  }

  Future<String> sourceCommit() =>
      _gitOutput(source.path, ['rev-parse', 'HEAD']);

  Future<void> advanceSource() async {
    await File(
      p.join(source.path, 'revision.txt'),
    ).writeAsString(DateTime.now().microsecondsSinceEpoch.toString());
    await _git(source.path, ['add', '.']);
    await _git(source.path, ['commit', '-q', '-m', 'Advance Profile']);
  }

  test('resolves a Git Profile and writes a lock', () async {
    final result = await WayfinderProfileResolver(
      dataDirectory: data,
    ).resolve(project.path);
    expect(result.direct, isTrue);
    expect(result.reused, isFalse);
    expect(result.upgraded, isFalse);
    final lock =
        jsonDecode(await File(result.lockPath).readAsString())
            as Map<String, Object?>;
    expect(lock['lock_version'], 1);
    expect(lock['configuration_sha256'], isA<String>());
    final profile =
        (lock['profiles']! as Map<String, Object?>)['bitwild_profile']!
            as Map<String, Object?>;
    expect(profile['requested_ref'], 'v2026.3');
    expect(profile['profile_release'], '2026.3');
    expect(profile['resolved_commit'], isA<String>());
  });

  test(
    'resolves a relative local Git source from the configuration root',
    () async {
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['git'] =
          '../source';
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      final resolved = await resolver.resolve(project.path);
      expect(resolved.bindings['bitwild_profile']?.release, '2026.3');
      final lock =
          jsonDecode(
                await File(
                  p.join(project.path, 'wayfinder.lock'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(
        (lock['profiles'] as Map)['bitwild_profile']['source'],
        '../source',
      );
      final readOnly = await resolver.readLockedForBundle(
        p.join(project.path, 'knowledge'),
      );
      expect(readOnly?.bindings['bitwild_profile']?.release, '2026.3');
    },
  );

  test('reuses a current lock and cache without resolving again', () async {
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    await resolver.resolve(project.path);
    final second = await resolver.resolve(project.path);
    expect(second.reused, isTrue);
    expect(second.upgraded, isFalse);
  });

  test(
    'canonical hash ignores formatting and object key order, but not arrays',
    () {
      final original = WayfinderProfileResolver.canonicalConfigurationSha256(
        '{"version":1,"profiles":{"x":{"applies_to":["a","b"]}}}',
      );
      expect(
        WayfinderProfileResolver.canonicalConfigurationSha256(
          '{ "profiles": {"x": {"applies_to": ["a", "b"]}}, "version": 1 }',
        ),
        original,
      );
      expect(
        WayfinderProfileResolver.canonicalConfigurationSha256(
          '{"version":1,"profiles":{"x":{"applies_to":["b","a"]}}}',
        ),
        isNot(original),
      );
    },
  );

  test('get keeps a locked branch while upgrade advances it', () async {
    final branch = await _gitOutput(source.path, [
      'symbolic-ref',
      '--short',
      'HEAD',
    ]);
    final value = await config();
    (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = branch;
    await saveConfig(value);
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    await resolver.resolve(project.path);
    final first = await lockCommit();
    await advanceSource();
    expect(await sourceCommit(), isNot(first));
    expect((await resolver.resolve(project.path)).reused, isTrue);
    expect(await lockCommit(), first);
    final upgraded = await resolver.resolve(project.path, upgrade: true);
    expect(upgraded.upgraded, isTrue);
    expect(await lockCommit(), await sourceCommit());
  });

  test(
    'a pinned commit and current lock work without the source repository',
    () async {
      final commit = await sourceCommit();
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = commit;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      await source.rename(p.join(temp.path, 'source-moved'));
      expect((await resolver.resolve(project.path)).reused, isTrue);
      expect(
        (await resolver.resolve(project.path, upgrade: true)).upgraded,
        isTrue,
      );
      expect(await lockCommit(), commit);
    },
  );

  test('upgrade follows a moved tag while get retains its lock', () async {
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    await resolver.resolve(project.path);
    final first = await lockCommit();
    await advanceSource();
    await _git(source.path, ['tag', '-f', 'v2026.3']);
    expect((await resolver.resolve(project.path)).reused, isTrue);
    expect(await lockCommit(), first);
    await resolver.resolve(project.path, upgrade: true);
    expect(await lockCommit(), await sourceCommit());
  });

  test('get resolves the current branch when the lock is missing', () async {
    final branch = await _gitOutput(source.path, [
      'symbolic-ref',
      '--short',
      'HEAD',
    ]);
    final value = await config();
    (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = branch;
    await saveConfig(value);
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    await resolver.resolve(project.path);
    final first = await lockCommit();
    await advanceSource();
    await File(p.join(project.path, 'wayfinder.lock')).delete();
    expect((await resolver.resolve(project.path)).reused, isFalse);
    expect(await lockCommit(), await sourceCommit());
    expect(await lockCommit(), isNot(first));
  });

  test(
    'missing cache recovers the exact locked commit after a branch moves',
    () async {
      final branch = await _gitOutput(source.path, [
        'symbolic-ref',
        '--short',
        'HEAD',
      ]);
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = branch;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final before = await lockCommit();
      await advanceSource();
      await data.delete(recursive: true);
      expect((await resolver.resolve(project.path)).reused, isFalse);
      expect(await lockCommit(), before);
    },
  );

  test(
    'unavailable locked commit fails without silently moving the branch',
    () async {
      final branch = await _gitOutput(source.path, [
        'symbolic-ref',
        '--short',
        'HEAD',
      ]);
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = branch;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final before = await File(
        p.join(project.path, 'wayfinder.lock'),
      ).readAsString();
      await data.delete(recursive: true);
      await source.delete(recursive: true);
      await Directory(p.join(source.path, 'profile')).create(recursive: true);
      await File(
        '../../profile/wayfinder-profile.json',
      ).copy(p.join(source.path, 'profile', 'wayfinder-profile.json'));
      await _git(source.path, ['init', '-q', '-b', branch]);
      await _git(source.path, ['config', 'user.email', 'test@example.test']);
      await _git(source.path, ['config', 'user.name', 'Wayfinder Test']);
      await _git(source.path, ['add', '.']);
      await _git(source.path, [
        'commit',
        '-q',
        '-m',
        'Unrelated Profile history',
      ]);
      expect(
        resolver.resolve(project.path),
        throwsA(isA<WayfinderProfileResolutionException>()),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
        before,
      );
    },
  );

  test(
    'semantic configuration changes keep the prior resolved commit',
    () async {
      final branch = await _gitOutput(source.path, [
        'symbolic-ref',
        '--short',
        'HEAD',
      ]);
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = branch;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final first = await lockCommit();
      await advanceSource();
      value['profiles']['bitwild_profile']['tags'] = [
        {'name': 'project-topic', 'description': 'A project topic'},
      ];
      await saveConfig(value);
      expect((await resolver.resolve(project.path)).reused, isFalse);
      expect(await lockCommit(), first);
    },
  );

  test(
    'a manifest outside its schema fails at the offending pointer',
    () async {
      final manifest = File(
        p.join(source.path, 'profile', 'wayfinder-profile.json'),
      );
      final invalid =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      (invalid['standard_types'] as List<dynamic>).add({'name': 'Extra'});
      await manifest.writeAsString(jsonEncode(invalid));
      await _git(source.path, ['commit', '-qam', 'Invalid Profile']);
      await _git(source.path, ['tag', '-f', 'v2026.3']);
      final index = (invalid['standard_types'] as List<dynamic>).length - 1;
      expect(
        WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
        throwsA(
          isA<WayfinderProfileResolutionException>().having(
            (error) => error.message,
            'message',
            endsWith(
              'manifest is invalid at /standard_types/$index: '
              'is missing required property description.',
            ),
          ),
        ),
      );
    },
  );

  test('bad manifest on upgrade leaves the previous lock intact', () async {
    final branch = await _gitOutput(source.path, [
      'symbolic-ref',
      '--short',
      'HEAD',
    ]);
    final value = await config();
    (value['profiles']['bitwild_profile']['source'] as Map)['ref'] = branch;
    await saveConfig(value);
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    await resolver.resolve(project.path);
    final before = await File(
      p.join(project.path, 'wayfinder.lock'),
    ).readAsString();
    final manifest = File(
      p.join(source.path, 'profile', 'wayfinder-profile.json'),
    );
    final invalid =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    invalid['release'] = '2099.1';
    await manifest.writeAsString(jsonEncode(invalid));
    await _git(source.path, ['add', '.']);
    await _git(source.path, ['commit', '-q', '-m', 'Invalid Profile']);
    expect(
      resolver.resolve(project.path, upgrade: true),
      throwsA(isA<WayfinderProfileResolutionException>()),
    );
    expect(
      await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
      before,
    );
    expect((await resolver.resolve(project.path)).reused, isTrue);
  });

  test(
    'missing source path and malformed lock fail or refresh safely',
    () async {
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final original = await File(
        p.join(project.path, 'wayfinder.lock'),
      ).readAsString();
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['path'] =
          'missing';
      await saveConfig(value);
      expect(
        resolver.resolve(project.path),
        throwsA(isA<WayfinderProfileResolutionException>()),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
        original,
      );
      (value['profiles']['bitwild_profile']['source'] as Map)['path'] =
          'profile';
      await saveConfig(value);
      await File(
        p.join(project.path, 'wayfinder.lock'),
      ).writeAsString('{broken');
      expect((await resolver.resolve(project.path)).reused, isFalse);
      expect(await lockCommit(), await sourceCommit());
    },
  );

  test(
    'a bundle symlink outside the project fails before lock creation',
    () async {
      await Directory(p.join(project.path, 'knowledge')).delete();
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await Link(p.join(project.path, 'knowledge')).create(outside.path);
      expect(
        WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
        throwsA(isA<WayfinderProfileResolutionException>()),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    },
  );

  test('additive child Profile inherits compiled base vocabulary', () async {
    final child = Directory(p.join(source.path, 'child'));
    await child.create();
    await File(p.join(child.path, 'wayfinder-profile.json')).writeAsString(
      jsonEncode({
        'id': 'client_profile',
        'release': '2026.3',
        'implements': {'id': 'okf', 'release': '0.2'},
        'standard_types': [
          {'name': 'Client Note', 'description': 'A client-specific note'},
        ],
        'tags': [
          {'name': 'client-topic', 'description': 'A client topic'},
        ],
      }),
    );
    await _git(source.path, ['add', '.']);
    await _git(source.path, ['commit', '-q', '-m', 'Child Profile']);
    final branch = await _gitOutput(source.path, [
      'symbolic-ref',
      '--short',
      'HEAD',
    ]);
    await saveConfig({
      'version': 1,
      'profiles': {
        'bitwild_profile': {
          'source': {'git': source.path, 'ref': branch, 'path': 'profile'},
          'applies_to': [],
        },
        'client_profile': {
          'extends': 'bitwild_profile',
          'source': {'git': source.path, 'ref': branch, 'path': 'child'},
          'applies_to': ['./knowledge'],
        },
      },
    });
    final result = await WayfinderProfileResolver(
      dataDirectory: data,
    ).resolve(project.path);
    expect(
      result.bindings['client_profile']!.typeNames,
      containsAll(['Guide', 'Client Note']),
    );
    expect(
      result.bindings['client_profile']!.tagNames,
      contains('client-topic'),
    );
  });

  test(
    'missing Profile source does not prevent independent OKF validation or graph',
    () async {
      final fixture = Directory(
        '../../packages/wayfinder/test/fixtures/configured-project/knowledge',
      );
      await for (final entity in fixture.list()) {
        if (entity is File) {
          await entity.copy(
            p.join(project.path, 'knowledge', p.basename(entity.path)),
          );
        }
      }
      final value = await config();
      (value['profiles']['bitwild_profile']['source'] as Map)['ref'] =
          'missing-ref';
      await saveConfig(value);
      final output = <String>[];
      final errors = <String>[];
      final cli = WayfinderCli(
        out: output.add,
        err: errors.add,
        notices: false,
        profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
      );
      final bundle = p.join(project.path, 'knowledge');
      expect(await cli.run(['validate', bundle, '--output=json']), 2);
      final report = jsonDecode(output.single) as Map<String, dynamic>;
      expect((report['okf'] as Map)['state'], 'PASS');
      expect((report['profile'] as Map)['state'], 'UNSUPPORTED');
      expect(errors, isEmpty);
      output.clear();
      expect(await cli.run(['graph', bundle]), 0);
      expect(output.single, contains('nodes'));
      output.clear();
      expect(await cli.run(['get', project.path]), 2);
      expect(errors.last, contains('missing-ref'));
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    },
  );

  test(
    'validate is read-only until get prepares the selected Profile',
    () async {
      final fixture = Directory(
        '../../packages/wayfinder/test/fixtures/configured-project/knowledge',
      );
      await for (final entity in fixture.list()) {
        if (entity is File) {
          await entity.copy(
            p.join(project.path, 'knowledge', p.basename(entity.path)),
          );
        }
      }
      final value = await config();
      value['profiles']['bitwild_profile']['actors'] = {
        'process:fixture': {'name': 'Fixture process'},
      };
      value['profiles']['bitwild_profile']['tags'] = [
        {'name': 'governance', 'description': 'Governance topic'},
      ];
      await saveConfig(value);
      final output = <String>[];
      final errors = <String>[];
      final cli = WayfinderCli(
        out: output.add,
        err: errors.add,
        notices: false,
        profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
      );
      final bundle = p.join(project.path, 'knowledge');
      expect(await cli.run(['validate', bundle, '--output=json']), 2);
      expect(errors, isEmpty);
      final unresolved = jsonDecode(output.single) as Map<String, dynamic>;
      expect((unresolved['okf'] as Map)['state'], 'PASS');
      expect((unresolved['profile'] as Map)['state'], 'UNSUPPORTED');
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
      output.clear();
      expect(await cli.run(['get', project.path]), 0);
      final lock = File(p.join(project.path, 'wayfinder.lock'));
      expect(await lock.exists(), isTrue);
      final lockedBytes = await lock.readAsBytes();
      output.clear();
      expect(await cli.run(['validate', bundle, '--output=json']), 0);
      final report = jsonDecode(output.single) as Map<String, dynamic>;
      expect((report['profile'] as Map)['state'], 'PASS');
      expect(await lock.readAsBytes(), lockedBytes);

      (value['profiles']['bitwild_profile']['tags'] as List).add({
        'name': 'new-topic',
        'description': 'A new project topic',
      });
      await saveConfig(value);
      output.clear();
      expect(await cli.run(['validate', bundle, '--output=json']), 2);
      final stale = jsonDecode(output.single) as Map<String, dynamic>;
      expect((stale['okf'] as Map)['state'], 'PASS');
      expect((stale['profile'] as Map)['state'], 'UNSUPPORTED');
      expect(await lock.readAsBytes(), lockedBytes);
    },
  );

  test('CLI get and upgrade use the shared resolver', () async {
    final output = <String>[];
    final errors = <String>[];
    final cli = WayfinderCli(
      out: output.add,
      err: errors.add,
      notices: false,
      profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
    );
    expect(await cli.run(['get', project.path, '--output=json']), 0);
    expect(jsonDecode(output.single), containsPair('direct', true));
    output.clear();
    expect(await cli.run(['upgrade', project.path, '--output=json']), 0);
    expect(jsonDecode(output.single), containsPair('upgraded', true));
    expect(errors, isEmpty);
  });
}

Future<void> _git(String directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

Future<String> _gitOutput(String directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}
