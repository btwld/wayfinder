import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/profile_resolver.dart';

import 'support.dart';

final _bitwild = ProfileId.parse('bitwild-profile');
final _client = ProfileId.parse('client-profile');

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
    await copyBitwildPackage(source.path);
    await _git(source.path, ['add', '.']);
    await _git(source.path, ['commit', '-q', '-m', 'Profile']);
    await _git(source.path, ['tag', 'v2026.3']);
    await File(p.join(project.path, 'wayfinder.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'profiles': {
          'bitwild-profile': {
            'source': {
              'git': source.path,
              'ref': 'v2026.3',
              'path': 'profiles/bitwild',
            },
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
    return (lock['packages']
            as Map<String, dynamic>)['bitwild-profile']['resolved_commit']
        as String;
  }

  Future<Map<String, dynamic>> readLock() async =>
      jsonDecode(
            await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
          )
          as Map<String, dynamic>;

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
    expect(result.reused, isFalse);
    expect(result.upgraded, isFalse);
    final lock =
        jsonDecode(await File(result.lockPath).readAsString())
            as Map<String, Object?>;
    expect(lock.keys, ['lock_version', 'configuration_sha256', 'packages']);
    expect(lock['lock_version'], 1);
    expect(lock['configuration_sha256'], isA<String>());
    expect(lock['packages'], {
      'bitwild-profile': {
        'source': source.path,
        'requested_ref': 'v2026.3',
        'resolved_commit': await sourceCommit(),
        'path': 'profiles/bitwild',
        'release': '2026.3',
      },
    });
    expect(result.packages[_bitwild]?.extendsId, isNull);
  });

  test(
    'resolves a relative local Git source from the configuration root',
    () async {
      final value = await config();
      (value['profiles']['bitwild-profile']['source'] as Map)['git'] =
          '../source';
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      final resolved = await resolver.resolve(project.path);
      expect(resolved.packages[_bitwild]?.release, '2026.3');
      expect(
        ((await readLock())['packages'] as Map)['bitwild-profile']['source'],
        '../source',
      );
      final selection = await resolver.select(
        p.join(project.path, 'knowledge'),
      );
      expect((selection as SelectedProfile).profile.selected.release, '2026.3');
    },
  );

  test(
    'get twice fetches nothing and leaves the lock byte-identical',
    () async {
      final calls = <List<String>>[];
      final resolver = WayfinderProfileResolver(
        dataDirectory: data,
        git: _spy(calls),
      );
      await resolver.resolve(project.path);
      final lock = File(p.join(project.path, 'wayfinder.lock'));
      final first = await lock.readAsBytes();
      final modified = await lock.lastModified();
      calls.clear();
      final second = await resolver.resolve(project.path);
      expect(second.reused, isTrue);
      expect(second.upgraded, isFalse);
      expect(await lock.readAsBytes(), first);
      expect(await lock.lastModified(), modified);
      expect(calls.where(_fetches), isEmpty);
    },
  );

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
    (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
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
      (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = commit;
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
    (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
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
      (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
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
      (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final before = await File(
        p.join(project.path, 'wayfinder.lock'),
      ).readAsString();
      await data.delete(recursive: true);
      await source.delete(recursive: true);
      await copyBitwildPackage(source.path);
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
      await expectLater(
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
      (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final first = await lockCommit();
      await advanceSource();
      value['profiles']['bitwild-profile']['tags'] = [
        {'name': 'project-topic', 'description': 'A project topic'},
      ];
      await saveConfig(value);
      expect((await resolver.resolve(project.path)).reused, isFalse);
      expect(await lockCommit(), first);
    },
  );

  test('a package outside its schema fails at the offending path', () async {
    final manifest = File(
      p.join(source.path, 'profiles', 'bitwild', 'wayfinder-profile.json'),
    );
    final invalid =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    (invalid['types'] as List<dynamic>).add({'name': 'Extra'});
    await manifest.writeAsString(jsonEncode(invalid));
    await _git(source.path, ['commit', '-qam', 'Invalid Profile']);
    await _git(source.path, ['tag', '-f', 'v2026.3']);
    final index = (invalid['types'] as List<dynamic>).length - 1;
    expect(
      WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>()
            .having(
              (error) => error.code,
              'code',
              DiagnosticCode.profileInvalid,
            )
            .having(
              (error) => error.message,
              'message',
              endsWith(
                'cannot be evaluated by this validator: is missing required '
                'property description at types[$index].description.',
              ),
            ),
      ),
    );
  });

  test(
    'an unreadable package on upgrade leaves the previous lock intact',
    () async {
      final branch = await _gitOutput(source.path, [
        'symbolic-ref',
        '--short',
        'HEAD',
      ]);
      final value = await config();
      (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
      await saveConfig(value);
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final before = await File(
        p.join(project.path, 'wayfinder.lock'),
      ).readAsString();
      final manifest = File(
        p.join(source.path, 'profiles', 'bitwild', 'wayfinder-profile.json'),
      );
      final invalid =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      invalid['format'] = 3;
      await manifest.writeAsString(jsonEncode(invalid));
      await _git(source.path, ['add', '.']);
      await _git(source.path, ['commit', '-q', '-m', 'Invalid Profile']);
      await expectLater(
        resolver.resolve(project.path, upgrade: true),
        throwsA(
          isA<WayfinderProfileResolutionException>()
              .having(
                (error) => error.code,
                'code',
                DiagnosticCode.profileUnsupported,
              )
              .having(
                (error) => error.message,
                'message',
                contains('package format 3 is not supported'),
              ),
        ),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
        before,
      );
      expect((await resolver.resolve(project.path)).reused, isTrue);
    },
  );

  test(
    'missing source path and malformed lock fail or refresh safely',
    () async {
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      await resolver.resolve(project.path);
      final original = await File(
        p.join(project.path, 'wayfinder.lock'),
      ).readAsString();
      final value = await config();
      (value['profiles']['bitwild-profile']['source'] as Map)['path'] =
          'missing';
      await saveConfig(value);
      await expectLater(
        resolver.resolve(project.path),
        throwsA(isA<WayfinderProfileResolutionException>()),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
        original,
      );
      (value['profiles']['bitwild-profile']['source'] as Map)['path'] =
          'profiles/bitwild';
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
      await expectLater(
        WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
        throwsA(isA<WayfinderProfileResolutionException>()),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    },
  );

  Future<void> commitPackage(
    String directory,
    Map<String, Object?> package, {
    Directory? repository,
    String? tag,
  }) async {
    final root = repository ?? source;
    final target = Directory(p.join(root.path, directory));
    await target.create(recursive: true);
    await File(
      p.join(target.path, 'wayfinder-profile.json'),
    ).writeAsString(jsonEncode(package));
    await _git(root.path, ['add', '.']);
    await _git(root.path, ['commit', '-q', '-m', 'Package $directory']);
    if (tag != null) await _git(root.path, ['tag', tag]);
  }

  Future<void> bindOnly(
    String id,
    Map<String, Object?> source, {
    Map<String, Object?> additions = const {},
  }) => saveConfig({
    'version': 1,
    'profiles': {
      id: {
        'source': source,
        'applies_to': ['./knowledge'],
        ...additions,
      },
    },
  });

  test(
    'a package names its parent; the project never wires the chain',
    () async {
      await commitPackage('child', {
        'format': 2,
        'id': 'client-profile',
        'release': '3',
        'implements': {'id': 'okf', 'release': '0.2'},
        'extends': {'path': 'profiles/bitwild'},
        'types': [
          {'name': 'Client Note', 'description': 'A client-specific note'},
        ],
        'tags': [
          {'name': 'client-topic', 'description': 'A client topic'},
        ],
        'relationships': [
          {'name': 'escalated-to', 'description': 'A client escalation'},
        ],
        'rules': <Object?>[],
      }, tag: 'client-v3');
      await bindOnly(
        'client-profile',
        {'git': source.path, 'ref': 'client-v3', 'path': 'child'},
        additions: {
          'relationships': [
            {'name': 'runs-after', 'description': 'A project ordering'},
          ],
        },
      );
      final resolver = WayfinderProfileResolver(dataDirectory: data);
      final result = await resolver.resolve(project.path);
      final commit = await sourceCommit();
      expect(result.packages.keys, unorderedEquals([_bitwild, _client]));
      expect((await readLock())['packages'], {
        'bitwild-profile': {
          'source': source.path,
          'requested_ref': 'client-v3',
          'resolved_commit': commit,
          'path': 'profiles/bitwild',
          'release': '2026.3',
        },
        'client-profile': {
          'source': source.path,
          'requested_ref': 'client-v3',
          'resolved_commit': commit,
          'path': 'child',
          'release': '3',
          'extends': 'bitwild-profile',
        },
      });

      final selection =
          await resolver.select(p.join(project.path, 'knowledge'))
              as SelectedProfile;
      final composed = selection.profile;
      expect(composed.chain.map((package) => package.id), [_bitwild, _client]);
      expect(composed.selected.release, '3');
      expect(selection.commits, {_bitwild: commit, _client: commit});
      expect(
        composed.vocabulary.relationships,
        containsAll(['depends-on', 'escalated-to', 'runs-after']),
      );
      expect(composed.vocabulary.types, containsAll(['Guide', 'Client Note']));
      expect(composed.vocabulary.tags, contains('client-topic'));

      final colliding = await config();
      (colliding['profiles']['client-profile']['relationships'] as List).add({
        'name': 'escalated-to',
        'description': 'Repeats the child package',
      });
      await saveConfig(colliding);
      final locked = await File(
        p.join(project.path, 'wayfinder.lock'),
      ).readAsString();
      await expectLater(
        resolver.resolve(project.path),
        throwsA(
          isA<WayfinderProfileResolutionException>()
              .having(
                (error) => error.code,
                'code',
                DiagnosticCode.profileComposition,
              )
              .having(
                (error) => error.message,
                'message',
                'Profile client-profile: The project declares relationship '
                    'escalated-to, which Profile client-profile already '
                    'declares.',
              ),
        ),
      );
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
        locked,
        reason: 'composition runs at get, before the lock is written',
      );
    },
  );

  test('a parent at another revision resolves from its own ref', () async {
    final other = await Directory(p.join(temp.path, 'other')).create();
    await _git(other.path, ['init', '-q']);
    await _git(other.path, ['config', 'user.email', 'test@example.test']);
    await _git(other.path, ['config', 'user.name', 'Wayfinder Test']);
    await commitPackage(
      'profile',
      {
        'format': 2,
        'id': 'client-profile',
        'release': '1',
        'implements': {'id': 'okf', 'release': '0.2'},
        'extends': {
          'git': source.path,
          'ref': 'v2026.3',
          'path': 'profiles/bitwild',
        },
        'rules': <Object?>[],
      },
      repository: other,
      tag: 'client-v1',
    );
    await bindOnly('client-profile', {
      'git': other.path,
      'ref': 'client-v1',
      'path': 'profile',
    });
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    await resolver.resolve(project.path);
    final packages = (await readLock())['packages'] as Map<String, dynamic>;
    expect(packages['bitwild-profile'], {
      'source': source.path,
      'requested_ref': 'v2026.3',
      'resolved_commit': await sourceCommit(),
      'path': 'profiles/bitwild',
      'release': '2026.3',
    });
    expect(packages['client-profile']['source'], other.path);
    expect(packages['client-profile']['extends'], 'bitwild-profile');
    final selection = await resolver.select(p.join(project.path, 'knowledge'));
    expect(
      (selection as SelectedProfile).profile.chain.map((package) => package.id),
      [_bitwild, _client],
    );
  });

  test('two revisions of one Profile fail at get, naming both refs', () async {
    final base = await sourceCommit();
    await advanceSource();
    await _git(source.path, ['tag', 'v2026.4']);
    final other = await Directory(p.join(temp.path, 'other')).create();
    await _git(other.path, ['init', '-q']);
    await _git(other.path, ['config', 'user.email', 'test@example.test']);
    await _git(other.path, ['config', 'user.name', 'Wayfinder Test']);
    await commitPackage(
      'profile',
      {
        'format': 2,
        'id': 'client-profile',
        'release': '1',
        'implements': {'id': 'okf', 'release': '0.2'},
        'extends': {
          'git': source.path,
          'ref': 'v2026.4',
          'path': 'profiles/bitwild',
        },
        'rules': <Object?>[],
      },
      repository: other,
      tag: 'client-v1',
    );
    await Directory(p.join(project.path, 'client')).create();
    final value = await config();
    value['profiles']['client-profile'] = {
      'source': {'git': other.path, 'ref': 'client-v1', 'path': 'profile'},
      'applies_to': ['./client'],
    };
    await saveConfig(value);
    await expectLater(
      WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          'Profile bitwild-profile is needed from two sources: '
              '${source.path} profiles/bitwild at v2026.3 ($base) and '
              '${source.path} profiles/bitwild at v2026.4 '
              '(${await sourceCommit()}). A project locks one source per '
              'Profile id; the refs must agree.',
        ),
      ),
    );
    expect(
      await File(p.join(project.path, 'wayfinder.lock')).exists(),
      isFalse,
    );
  });

  group('a parent bound directly and reached through a child', () {
    late Directory other;

    Future<void> extendParentAt(String ref) async {
      other = await Directory(p.join(temp.path, 'other')).create();
      await _git(other.path, ['init', '-q']);
      await _git(other.path, ['config', 'user.email', 'test@example.test']);
      await _git(other.path, ['config', 'user.name', 'Wayfinder Test']);
      await commitPackage(
        'profile',
        {
          'format': 2,
          'id': 'client-profile',
          'release': '1',
          'implements': {'id': 'okf', 'release': '0.2'},
          'extends': {
            'git': source.path,
            'ref': ref,
            'path': 'profiles/bitwild',
          },
          'rules': <Object?>[],
        },
        repository: other,
        tag: 'client-v1',
      );
      await Directory(p.join(project.path, 'client')).create();
    }

    Map<String, Object?> direct() => {
      'source': {
        'git': source.path,
        'ref': 'v2026.3',
        'path': 'profiles/bitwild',
      },
      'applies_to': ['./knowledge'],
    };

    Map<String, Object?> child() => {
      'source': {'git': other.path, 'ref': 'client-v1', 'path': 'profile'},
      'applies_to': ['./client'],
    };

    test(
      'under two refs at one commit fails get, naming both sources',
      () async {
        await _git(source.path, ['branch', 'trunk']);
        await extendParentAt('trunk');
        final commit = await sourceCommit();
        final tagged = '${source.path} profiles/bitwild at v2026.3 ($commit)';
        final branched = '${source.path} profiles/bitwild at trunk ($commit)';
        final orders = [
          (
            {'bitwild-profile': direct(), 'client-profile': child()},
            tagged,
            branched,
          ),
          (
            {'client-profile': child(), 'bitwild-profile': direct()},
            branched,
            tagged,
          ),
        ];
        for (final (profiles, first, second) in orders) {
          await saveConfig({'version': 1, 'profiles': profiles});
          await expectLater(
            WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
            throwsA(
              isA<WayfinderProfileResolutionException>().having(
                (error) => error.message,
                'message',
                'Profile bitwild-profile is needed from two sources: $first and '
                    '$second. A project locks one source per Profile id; the '
                    'refs must agree.',
              ),
            ),
            reason: profiles.keys.join(' then '),
          );
          expect(
            await File(p.join(project.path, 'wayfinder.lock')).exists(),
            isFalse,
            reason: profiles.keys.join(' then '),
          );
        }
      },
    );

    test('under one ref locks it once, and get converges', () async {
      await extendParentAt('v2026.3');
      await saveConfig({
        'version': 1,
        'profiles': {'bitwild-profile': direct(), 'client-profile': child()},
      });
      final calls = <List<String>>[];
      final resolver = WayfinderProfileResolver(
        dataDirectory: data,
        git: _spy(calls),
      );
      await resolver.resolve(project.path);
      final packages = (await readLock())['packages'] as Map<String, dynamic>;
      expect(packages['bitwild-profile'], {
        'source': source.path,
        'requested_ref': 'v2026.3',
        'resolved_commit': await sourceCommit(),
        'path': 'profiles/bitwild',
        'release': '2026.3',
      });
      expect(packages['client-profile']['extends'], 'bitwild-profile');
      calls.clear();
      expect((await resolver.resolve(project.path)).reused, isTrue);
      expect(calls.where(_fetches), isEmpty);
      for (final bundle in ['knowledge', 'client']) {
        expect(
          await resolver.select(p.join(project.path, bundle)),
          isA<SelectedProfile>(),
          reason: bundle,
        );
      }
    });
  });

  test('get fetches a locked commit the mirror lacks', () async {
    final branch = await _gitOutput(source.path, [
      'symbolic-ref',
      '--short',
      'HEAD',
    ]);
    final value = await config();
    (value['profiles']['bitwild-profile']['source'] as Map)['ref'] = branch;
    await saveConfig(value);
    final calls = <List<String>>[];
    final resolver = WayfinderProfileResolver(
      dataDirectory: data,
      git: _spy(calls),
    );
    await resolver.resolve(project.path);
    await advanceSource();
    final pinned = await sourceCommit();
    final lock = await readLock();
    (lock['packages'] as Map)['bitwild-profile']['resolved_commit'] = pinned;
    await File(
      p.join(project.path, 'wayfinder.lock'),
    ).writeAsString(jsonEncode(lock));
    calls.clear();
    final result = await resolver.resolve(project.path);
    expect(result.reused, isFalse);
    expect(await lockCommit(), pinned);
    expect(calls.where(_fetches).map((call) => call.take(2).toList()), [
      ['remote', 'update'],
    ]);
    expect(
      await resolver.select(p.join(project.path, 'knowledge')),
      isA<SelectedProfile>(),
    );
  });

  test('git ignores the repository variables of a hook or worktree', () async {
    final unrelated = await Directory(p.join(temp.path, 'unrelated')).create();
    await _git(unrelated.path, ['init', '-q']);
    final environment = {
      ...Platform.environment,
      'GIT_DIR': p.join(unrelated.path, '.git'),
      'GIT_WORK_TREE': unrelated.path,
    };
    final resolver = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, binary = false}) => runGit(
        arguments,
        workingDirectory: workingDirectory,
        binary: binary,
        environment: environment,
      ),
    );
    await resolver.resolve(project.path);
    expect(await lockCommit(), await sourceCommit());
    expect(
      await resolver.select(p.join(project.path, 'knowledge')),
      isA<SelectedProfile>(),
    );
    final mirror = await Directory(p.join(data.path, 'profiles')).list().single;
    final gitDir = await runGit(
      ['rev-parse', '--git-dir'],
      workingDirectory: mirror.path,
      environment: environment,
    );
    expect(gitDir.stdout.toString().trim(), '.');
  });

  test('a package that extends itself fails at get', () async {
    await commitPackage('a', {
      'format': 2,
      'id': 'loop-a',
      'release': '1',
      'implements': {'id': 'okf', 'release': '0.2'},
      'extends': {'path': 'b'},
      'rules': <Object?>[],
    });
    await commitPackage('b', {
      'format': 2,
      'id': 'loop-b',
      'release': '1',
      'implements': {'id': 'okf', 'release': '0.2'},
      'extends': {'path': 'a'},
      'rules': <Object?>[],
    }, tag: 'loop');
    await bindOnly('loop-a', {'git': source.path, 'ref': 'loop', 'path': 'a'});
    await expectLater(
      WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          'Profile loop-a extends itself through loop-a, loop-b.',
        ),
      ),
    );
  });

  group('a child Profile package ships rules', () {
    Map<String, Object?> childPackage(Map<String, Object?> check) => {
      'format': 2,
      'id': 'client-profile',
      'release': '2026.3',
      'implements': {'id': 'okf', 'release': '0.2'},
      'extends': {'path': 'profiles/bitwild'},
      'docs': 'https://client.example/profile/README.md',
      'rules': [
        {
          'id': 'type-allowed',
          'category': 'vocabulary',
          'severity': 'error',
          'status': 'stable',
          'description':
              'A client concept is a Decision, an Analysis or a Question.',
          'message': 'Client bundles do not use the {type} type.',
          'check': check,
          if (!check.containsKey('builtin'))
            'tests': {
              'valid': [
                {'type': 'Decision'},
              ],
              'invalid': [
                {'type': 'Guide'},
              ],
            },
        },
      ],
    };

    const typeSubset = {
      'subject': 'concept',
      'schema': {
        'properties': {
          'type': {
            'enum': ['Decision', 'Analysis', 'Question'],
          },
        },
      },
    };

    late String bundle;
    late WayfinderCli cli;
    late List<String> output;
    late List<String> errors;

    Future<void> commitChild(Map<String, Object?> package, String tag) async {
      final child = Directory(p.join(source.path, 'child'));
      await child.create();
      await File(
        p.join(child.path, 'wayfinder-profile.json'),
      ).writeAsString(jsonEncode(package));
      await _git(source.path, ['add', '.']);
      await _git(source.path, ['commit', '-q', '-m', 'Child Profile $tag']);
      await _git(source.path, ['tag', tag]);
    }

    Future<void> configure(String ref) => bindOnly(
      'client-profile',
      {'git': source.path, 'ref': ref, 'path': 'child'},
      additions: {
        'actors': {
          'process:fixture': {'name': 'Fixture process'},
        },
        'tags': [
          {'name': 'governance', 'description': 'Governance topic'},
        ],
      },
    );

    setUp(() async {
      await commitChild(childPackage(typeSubset), 'child-good');
      await commitChild(
        childPackage({'builtin': 'nonexistent-check'}),
        'child-bad',
      );
      await commitChild({
        ...childPackage(typeSubset),
        'id': 'someone-else',
      }, 'child-misnamed');
      final fixture = Directory(
        '../../packages/wayfinder/test/fixtures/configured-project/knowledge',
      );
      bundle = p.join(project.path, 'knowledge');
      await for (final entity in fixture.list()) {
        if (entity is File) {
          await entity.copy(p.join(bundle, p.basename(entity.path)));
        }
      }
      await configure('child-good');
      output = [];
      errors = [];
      cli = WayfinderCli(
        out: output.add,
        err: errors.add,
        notices: false,
        profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
      );
    });

    test('its rules add findings in the child namespace', () async {
      final resolved = await WayfinderProfileResolver(
        dataDirectory: data,
      ).resolve(project.path);
      expect(resolved.packages[_client]?.extendsId, _bitwild);
      expect(resolved.packages[_bitwild]?.extendsId, isNull);
      final lock = await readLock();
      expect((lock['packages']['client-profile'] as Map).keys, [
        'source',
        'requested_ref',
        'resolved_commit',
        'path',
        'release',
        'extends',
      ]);
      final commit = resolved.packages[_client]!.commit;

      expect(await cli.run(['validate', bundle, '--output=json']), 1);
      final report = jsonDecode(output.single) as Map<String, dynamic>;
      final profile = report['profile'] as Map<String, dynamic>;
      expect(profile['state'], 'FAIL');
      expect(profile['id'], 'client-profile');
      expect(profile['release'], '2026.3');
      expect(profile['chain'], [
        {'id': 'bitwild-profile', 'release': '2026.3', 'commit': commit},
        {'id': 'client-profile', 'release': '2026.3', 'commit': commit},
      ]);
      expect(profile['findings'], [
        {
          'id': 'client-profile/type-allowed',
          'severity': 'error',
          'message': 'Client bundles do not use the Guide type.',
          'location': {'path': 'sample.md'},
          'profile_release': '2026.3',
          'help_uri': 'https://client.example/profile/README.md#type-allowed',
        },
      ]);
      expect(report['engine'], {'okf': okfPackageVersion});
      expect(errors, isEmpty);
    });

    test(
      'a package the engine cannot evaluate is NOT ASSESSED, never partial',
      () async {
        expect(await cli.run(['get', project.path]), 0);
        final lockFile = File(p.join(project.path, 'wayfinder.lock'));
        final locked = await lockFile.readAsString();

        await configure('child-bad');
        expect(await cli.run(['get', project.path]), 2);
        expect(
          errors.single,
          allOf(
            contains('cannot be evaluated by this validator'),
            contains(
              'unknown builtin nonexistent-check; this wayfinder provides '
              'files-present, path-targets-exist, matches-generated at '
              'rules[0].check.builtin',
            ),
          ),
        );
        expect(await lockFile.readAsString(), locked);

        final raw = await File(
          p.join(project.path, 'wayfinder.json'),
        ).readAsString();
        final bad = await _gitOutput(source.path, [
          'rev-parse',
          'child-bad^{commit}',
        ]);
        await lockFile.writeAsString(
          jsonEncode({
            'lock_version': 1,
            'configuration_sha256':
                WayfinderProfileResolver.canonicalConfigurationSha256(raw),
            'packages': {
              'bitwild-profile': {
                'source': source.path,
                'requested_ref': 'child-bad',
                'resolved_commit': bad,
                'path': 'profiles/bitwild',
                'release': '2026.3',
              },
              'client-profile': {
                'source': source.path,
                'requested_ref': 'child-bad',
                'resolved_commit': bad,
                'path': 'child',
                'release': '2026.3',
                'extends': 'bitwild-profile',
              },
            },
          }),
        );
        output.clear();
        errors.clear();
        expect(await cli.run(['validate', bundle, '--output=json']), 2);
        final report = jsonDecode(output.single) as Map<String, dynamic>;
        expect((report['okf'] as Map)['state'], 'PASS');
        final profile = report['profile'] as Map<String, dynamic>;
        expect(profile['state'], 'NOT ASSESSED');
        expect(profile['findings'], isEmpty);
        final diagnostic = (report['diagnostics'] as List).single as Map;
        expect(diagnostic['id'], 'wayfinder/profile-unsupported');
        expect(
          diagnostic['message'],
          contains('unknown builtin nonexistent-check'),
        );
        expect(report['gate'], {'state': 'INCOMPLETE'});
        expect(errors, isEmpty);
      },
    );

    test(
      'a package-declared parent keeps its findings byte-identical',
      () async {
        final index = File(p.join(bundle, 'index.md'));
        await index.writeAsString(
          (await index.readAsString()).replaceFirst(
            'A sample guide.',
            'An edited guide.',
          ),
        );
        Future<List<Object?>> findings() async {
          output.clear();
          expect(await cli.run(['get', project.path]), 0);
          output.clear();
          await cli.run(['validate', bundle, '--output=json']);
          final report = jsonDecode(output.single) as Map<String, dynamic>;
          return (report['profile'] as Map)['findings'] as List<Object?>;
        }

        final child = await findings();
        await bindOnly(
          'bitwild-profile',
          {'git': source.path, 'ref': 'child-good', 'path': 'profiles/bitwild'},
          additions: {
            'actors': {
              'process:fixture': {'name': 'Fixture process'},
            },
            'tags': [
              {'name': 'governance', 'description': 'Governance topic'},
            ],
          },
        );
        final parent = await findings();
        expect(parent.map((f) => (f! as Map)['id']), [
          'bitwild-profile/index-current',
        ]);
        expect(
          jsonEncode([
            for (final finding in child)
              if (((finding! as Map)['id'] as String).startsWith('bitwild-'))
                finding,
          ]),
          jsonEncode(parent),
        );
        expect(child.map((f) => (f! as Map)['id']).toSet(), {
          'bitwild-profile/index-current',
          'client-profile/type-allowed',
        });
      },
    );

    test('a package must declare the id the configuration names', () async {
      await configure('child-misnamed');
      await expectLater(
        WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
        throwsA(
          isA<WayfinderProfileResolutionException>()
              .having(
                (error) => error.code,
                'code',
                DiagnosticCode.profileInvalid,
              )
              .having(
                (error) => error.message,
                'message',
                contains(
                  'declares id someone-else; the configuration names it '
                  'client-profile',
                ),
              ),
        ),
      );
    });
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
      (value['profiles']['bitwild-profile']['source'] as Map)['ref'] =
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
      expect((report['profile'] as Map)['state'], 'NOT ASSESSED');
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
      value['profiles']['bitwild-profile']['actors'] = {
        'process:fixture': {'name': 'Fixture process'},
      };
      value['profiles']['bitwild-profile']['tags'] = [
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
      expect((unresolved['profile'] as Map)['state'], 'NOT ASSESSED');
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

      (value['profiles']['bitwild-profile']['tags'] as List).add({
        'name': 'new-topic',
        'description': 'A new project topic',
      });
      await saveConfig(value);
      output.clear();
      expect(await cli.run(['validate', bundle, '--output=json']), 2);
      final stale = jsonDecode(output.single) as Map<String, dynamic>;
      expect((stale['okf'] as Map)['state'], 'PASS');
      expect((stale['profile'] as Map)['state'], 'NOT ASSESSED');
      expect(await lock.readAsBytes(), lockedBytes);
    },
  );

  test('validate --fix writes generated indexes, then passes', () async {
    final bundle = p.join(project.path, 'knowledge');
    await File(p.join(bundle, 'log.md')).writeAsString(
      '# Bundle Update Log\n\n## 2026-10-01\n\n'
      '* **Creation**: Created the bundle.\n',
    );
    await Directory(p.join(bundle, 'billing')).create();
    await File(p.join(bundle, 'billing', 'invoice.md')).writeAsString(
      '---\ntype: Guide\ntitle: Invoice\n'
      'description: How invoices are issued.\nstatus: stable\n---\n\n'
      '# Invoice\n',
    );
    await File(p.join(bundle, 'index.md')).writeAsString(
      '---\nokf_version: "0.2"\n---\n\n# Bundle\n\n'
      '* [Knowledge Log](log.md)\n\n# Directories\n\n'
      '* [billing](billing/)\n',
    );
    final output = <String>[];
    final errors = <String>[];
    final cli = WayfinderCli(
      out: output.add,
      err: errors.add,
      notices: false,
      profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
    );
    expect(await cli.run(['get', project.path]), 0);

    output.clear();
    expect(await cli.run(['validate', bundle]), 1);
    expect(output, contains(contains('bitwild-profile/index-current')));

    output.clear();
    expect(await cli.run(['validate', bundle, '--fix']), 0);
    expect(output.take(2), [
      'Fix: wrote billing/index.md',
      'Fix: wrote index.md',
    ]);
    expect(output, contains('Profile bitwild-profile 2026.3: PASS'));
    expect(
      await File(p.join(bundle, 'billing', 'index.md')).readAsString(),
      '# Guide\n\n* [Invoice](invoice.md) - How invoices are issued.\n',
    );
    final fixed = await _snapshot(bundle);

    output.clear();
    expect(await cli.run(['validate', bundle, '--fix', '--output=json']), 0);
    final again = jsonDecode(output.single) as Map<String, dynamic>;
    expect(again['fix'], {'written': <String>[]});
    expect(again['diagnostics'], isEmpty);
    expect((again['profile'] as Map)['state'], 'PASS');
    expect(await _snapshot(bundle), fixed);
    expect(errors, isEmpty);
  });

  test('a Profile with no Bitwild resolves and validates on its own', () async {
    final acme = Directory(p.join(source.path, 'acme'));
    await acme.create();
    await File(p.join(acme.path, 'wayfinder-profile.json')).writeAsString(
      jsonEncode({
        'format': 2,
        'id': 'acme-notes',
        'release': '1.0',
        'implements': {'id': 'okf', 'release': '0.2'},
        'docs': 'https://git.acme.example/notes-profile/blob/v1.0/README.md',
        'types': [
          {'name': 'Runbook', 'description': 'Steps to operate a system'},
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
        ],
        r'$defs': {
          'type-name': {'x-slot': 'profile.types'},
        },
      }),
    );
    await _git(source.path, ['add', '.']);
    await _git(source.path, ['commit', '-q', '-m', 'Acme Profile']);
    await _git(source.path, ['tag', 'acme-v1.0']);
    final fixture = Directory(
      '../../packages/wayfinder/test/fixtures/configured-project/knowledge',
    );
    final bundle = p.join(project.path, 'knowledge');
    await for (final entity in fixture.list()) {
      if (entity is File) {
        await entity.copy(p.join(bundle, p.basename(entity.path)));
      }
    }
    final entry = {
      'source': {'git': source.path, 'ref': 'acme-v1.0', 'path': 'acme'},
      'applies_to': ['./knowledge'],
      'actors': {
        'process:fixture': {'name': 'Fixture process'},
      },
      'tags': [
        {'name': 'governance', 'description': 'Governance topic'},
      ],
    };
    await saveConfig({
      'version': 1,
      'profiles': {'acme-notes': entry},
    });
    final resolver = WayfinderProfileResolver(dataDirectory: data);
    final resolved = await resolver.resolve(project.path);
    final acmeId = ProfileId.parse('acme-notes');
    expect(resolved.packages.keys, [acmeId]);
    final lock = await readLock();
    expect((lock['packages'] as Map).keys, ['acme-notes']);
    expect(lock['packages']['acme-notes']['release'], '1.0');

    final output = <String>[];
    final errors = <String>[];
    final cli = WayfinderCli(
      out: output.add,
      err: errors.add,
      notices: false,
      profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
    );
    expect(await cli.run(['validate', bundle, '--output=json']), 1);
    var report = jsonDecode(output.single) as Map<String, dynamic>;
    expect((report['profile'] as Map)['release'], '1.0');
    expect((report['profile'] as Map)['findings'], [
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
    expect(report['gate'], {'state': 'FAIL'});

    entry['types'] = [
      {'name': 'Guide', 'description': 'A guide'},
    ];
    await saveConfig({
      'version': 1,
      'profiles': {'acme-notes': entry},
    });
    expect(await cli.run(['get', project.path]), 0);
    output.clear();
    expect(await cli.run(['validate', bundle, '--output=json']), 0);
    report = jsonDecode(output.single) as Map<String, dynamic>;
    expect((report['profile'] as Map)['state'], 'PASS');
    expect((report['profile'] as Map)['findings'], isEmpty);
    expect((report['diagnostics'] as List).map((d) => (d as Map)['id']), [
      'wayfinder/project-type',
    ]);
    expect(report['gate'], {'state': 'PASS'});
    expect(errors, isEmpty);
  });

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
    expect(
      (jsonDecode(output.single) as Map)['packages'],
      contains('bitwild-profile'),
    );
    output.clear();
    expect(await cli.run(['upgrade', project.path, '--output=json']), 0);
    expect(jsonDecode(output.single), containsPair('upgraded', true));
    expect(errors, isEmpty);
  });

  group('select', () {
    late Map<String, String> tags;
    late List<List<String>> calls;
    late WayfinderProfileResolver resolver;
    late String bundle;

    Future<void> writeLock(Map<String, Object?> packages) async {
      final raw = await File(
        p.join(project.path, 'wayfinder.json'),
      ).readAsString();
      await File(p.join(project.path, 'wayfinder.lock')).writeAsString(
        jsonEncode({
          'lock_version': 1,
          'configuration_sha256':
              WayfinderProfileResolver.canonicalConfigurationSha256(raw),
          'packages': packages,
        }),
      );
    }

    Map<String, Object?> locked(
      String tag,
      String path, {
      String release = '2026.3',
      String? extendsId,
    }) => {
      'source': source.path,
      'requested_ref': tag,
      'resolved_commit': tags[tag]!,
      'path': path,
      'release': release,
      'extends': ?extendsId,
    };

    setUp(() async {
      Map<String, Object?> package(String id, {Object? extend}) => {
        'format': 2,
        'id': id,
        'release': '2026.3',
        'implements': {'id': 'okf', 'release': '0.2'},
        'extends': ?extend,
        'rules': <Object?>[],
      };
      await commitPackage(
        'child',
        package('client-profile', extend: {'path': 'profiles/bitwild'}),
        tag: 'arm-child',
      );
      await commitPackage(
        'misnamed',
        package('someone-else'),
        tag: 'arm-misnamed',
      );
      await commitPackage('unsupported', {
        ...package('client-profile'),
        'format': 3,
      }, tag: 'arm-unsupported');
      tags = {
        for (final tag in [
          'v2026.3',
          'arm-child',
          'arm-misnamed',
          'arm-unsupported',
        ])
          tag: await _gitOutput(source.path, ['rev-parse', '$tag^{commit}']),
      };
      calls = [];
      resolver = WayfinderProfileResolver(
        dataDirectory: data,
        git: _spy(calls),
      );
      await resolver.resolve(project.path);
      bundle = p.join(project.path, 'knowledge');
      calls.clear();
    });

    tearDown(() {
      expect(
        calls.where(_fetches),
        isEmpty,
        reason: 'validation never fetches',
      );
      expect(
        calls.map((call) => call.first).toSet().difference({
          'cat-file',
          'show',
        }),
        isEmpty,
        reason: 'select only reads the local mirror',
      );
    });

    Future<EngineDiagnostic> reason({String? configPath, String? at}) async {
      final selection = await resolver.select(
        at ?? bundle,
        configPath: configPath,
      );
      expect(selection, isA<UnselectedProfile>());
      return (selection as UnselectedProfile).reasons.single;
    }

    test('selects the locked chain with its commits', () async {
      final selection = await resolver.select(bundle) as SelectedProfile;
      expect(selection.profile.selected.id, _bitwild);
      expect(selection.commits, {_bitwild: tags['v2026.3']});
      expect(selection.config?.path, 'wayfinder.json');
    });

    test('config-missing when the named file does not exist', () async {
      final missing = p.join(project.path, 'missing.json');
      final diagnostic = await reason(configPath: missing);
      expect(diagnostic.code, DiagnosticCode.configMissing);
      expect(diagnostic.message, 'Configuration file $missing does not exist.');
    });

    test('config-invalid when wayfinder.json does not parse', () async {
      await File(p.join(project.path, 'wayfinder.json')).writeAsString('{');
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.configInvalid);
      expect(diagnostic.location?.path, 'wayfinder.json');
    });

    test('bundle-unbound when no entry applies to the bundle', () async {
      final other = await Directory(p.join(project.path, 'other')).create();
      final diagnostic = await reason(at: other.path);
      expect(diagnostic.code, DiagnosticCode.bundleUnbound);
      expect(
        diagnostic.message,
        'Bundle ${other.path} is not listed in wayfinder.json.',
      );
    });

    test('profile-unresolved without a lock', () async {
      await File(p.join(project.path, 'wayfinder.lock')).delete();
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnresolved);
      expect(
        diagnostic.message,
        'Profile lock is missing or unreadable. Run wayfinder get.',
      );
      expect(diagnostic.location?.path, 'wayfinder.json');
    });

    test('profile-unresolved when the configuration changed', () async {
      final value = await config();
      value['profiles']['bitwild-profile']['tags'] = [
        {'name': 'new-topic', 'description': 'A new topic'},
      ];
      await saveConfig(value);
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnresolved);
      expect(
        diagnostic.message,
        'Profile lock is stale: the configuration changed after wayfinder '
        'get. Run wayfinder get.',
      );
    });

    test('profile-unresolved when the lock lacks the chain', () async {
      await writeLock({
        'client-profile': locked(
          'arm-child',
          'child',
          extendsId: 'bitwild-profile',
        ),
      });
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnresolved);
      expect(
        diagnostic.message,
        'Profile lock has no complete chain for Profile bitwild-profile. '
        'Run wayfinder get.',
      );
    });

    test('profile-unresolved when the cache lacks a locked package', () async {
      await data.delete(recursive: true);
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnresolved);
      expect(
        diagnostic.message,
        'Profile bitwild-profile at ${source.path} (${tags['v2026.3']}) is '
        'not in the local cache. Run wayfinder get.',
      );
    });

    test('profile-unresolved when the package release differs', () async {
      await writeLock({
        'bitwild-profile': locked(
          'v2026.3',
          'profiles/bitwild',
          release: '2026.9',
        ),
      });
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnresolved);
      expect(
        diagnostic.message,
        'Profile bitwild-profile at ${tags['v2026.3']} declares release '
        '2026.3; the lock records 2026.9. Run wayfinder get.',
      );
    });

    test('profile-unresolved when the package parent differs', () async {
      await bindOnly('client-profile', {
        'git': source.path,
        'ref': 'arm-child',
        'path': 'child',
      });
      await writeLock({'client-profile': locked('arm-child', 'child')});
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnresolved);
      expect(
        diagnostic.message,
        'Profile client-profile at ${tags['arm-child']} declares another '
        'parent than the lock records. Run wayfinder get.',
      );
    });

    test('profile-invalid when the package declares another id', () async {
      await bindOnly('client-profile', {
        'git': source.path,
        'ref': 'arm-misnamed',
        'path': 'misnamed',
      });
      await writeLock({'client-profile': locked('arm-misnamed', 'misnamed')});
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileInvalid);
      expect(
        diagnostic.message,
        'Profile package misnamed at ${source.path} (${tags['arm-misnamed']}) '
        'declares id someone-else; the lock names it client-profile.',
      );
    });

    test('profile-unsupported when the package format is unknown', () async {
      await bindOnly('client-profile', {
        'git': source.path,
        'ref': 'arm-unsupported',
        'path': 'unsupported',
      });
      await writeLock({
        'client-profile': locked('arm-unsupported', 'unsupported'),
      });
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileUnsupported);
      expect(diagnostic.message, contains('package format 3 is not supported'));
    });

    test('profile-composition when the project repeats a chain name', () async {
      final value = await config();
      value['profiles']['bitwild-profile']['tags'] = [
        {'name': 'draft', 'description': 'Collides with an OKF status'},
      ];
      await saveConfig(value);
      await writeLock({
        'bitwild-profile': locked('v2026.3', 'profiles/bitwild'),
      });
      final diagnostic = await reason();
      expect(diagnostic.code, DiagnosticCode.profileComposition);
      expect(
        diagnostic.message,
        'Profile bitwild-profile: The project declares tag draft, which '
        'equals an OKF status value.',
      );
    });
  });
}

Future<Map<String, List<int>>> _snapshot(String root) async => {
  await for (final entity in Directory(root).list(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: root): await entity.readAsBytes(),
};

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

GitRunner _spy(List<List<String>> calls) =>
    (arguments, {workingDirectory, binary = false}) {
      calls.add(arguments);
      return runGit(
        arguments,
        workingDirectory: workingDirectory,
        binary: binary,
      );
    };

bool _fetches(List<String> call) => const {
  'clone',
  'fetch',
  'remote',
  'pull',
  'ls-remote',
}.contains(call.first);
