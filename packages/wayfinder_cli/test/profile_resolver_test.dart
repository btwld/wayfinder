import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/profile_resolver.dart';

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
    await Directory(
      p.join(source.path, 'profiles', 'bitwild'),
    ).create(recursive: true);
    await File('../../profiles/bitwild/wayfinder-profile.json').copy(
      p.join(source.path, 'profiles', 'bitwild', 'wayfinder-profile.json'),
    );
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
    return (lock['profiles']
            as Map<String, dynamic>)['bitwild-profile']['resolved_commit']
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
        (lock['profiles']! as Map<String, Object?>)['bitwild-profile']!
            as Map<String, Object?>;
    expect(profile['requested_ref'], 'v2026.3');
    expect(profile['profile_release'], '2026.3');
    expect(profile['resolved_commit'], isA<String>());
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
      expect(resolved.effective[_bitwild]?.selected.release, '2026.3');
      final lock =
          jsonDecode(
                await File(
                  p.join(project.path, 'wayfinder.lock'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(
        (lock['profiles'] as Map)['bitwild-profile']['source'],
        '../source',
      );
      final readOnly = await resolver.readLockedForBundle(
        p.join(project.path, 'knowledge'),
      );
      expect(readOnly?.effective[_bitwild]?.selected.release, '2026.3');
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
      await Directory(
        p.join(source.path, 'profiles', 'bitwild'),
      ).create(recursive: true);
      await File('../../profiles/bitwild/wayfinder-profile.json').copy(
        p.join(source.path, 'profiles', 'bitwild', 'wayfinder-profile.json'),
      );
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
      expect(
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

  test('a child Profile composes with its parent and the project', () async {
    final child = Directory(p.join(source.path, 'child'));
    await child.create();
    await File(p.join(child.path, 'wayfinder-profile.json')).writeAsString(
      jsonEncode({
        'format': 2,
        'id': 'client-profile',
        'release': '3',
        'implements': {'id': 'okf', 'release': '0.2'},
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
        'bitwild-profile': {
          'source': {
            'git': source.path,
            'ref': branch,
            'path': 'profiles/bitwild',
          },
          'applies_to': [],
        },
        'client-profile': {
          'extends': 'bitwild-profile',
          'source': {'git': source.path, 'ref': branch, 'path': 'child'},
          'applies_to': ['./knowledge'],
          'relationships': [
            {'name': 'runs-after', 'description': 'A project ordering'},
          ],
        },
      },
    });
    final result = await WayfinderProfileResolver(
      dataDirectory: data,
    ).resolve(project.path);
    final composed = result.effective[_client]!;
    expect(composed.chain.map((package) => package.id), [_bitwild, _client]);
    expect(composed.selected.release, '3');
    expect(
      composed.vocabulary.relationships,
      containsAll(['depends-on', 'escalated-to', 'runs-after']),
    );
    expect(composed.vocabulary.types, containsAll(['Guide', 'Client Note']));
    expect(composed.vocabulary.tags, contains('client-topic'));
    expect(result.effective[_bitwild]!.chain, hasLength(1));
    final lock =
        jsonDecode(
              await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
            )
            as Map<String, dynamic>;
    expect(lock['profiles']['client-profile']['profile_release'], '3');

    final colliding = await config();
    (colliding['profiles']['client-profile']['relationships'] as List).add({
      'name': 'escalated-to',
      'description': 'Repeats the child package',
    });
    await saveConfig(colliding);
    await expectLater(
      WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
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
    final taggedLikeRelationship = await config();
    (taggedLikeRelationship['profiles']['client-profile']['relationships']
            as List)
        .removeLast();
    taggedLikeRelationship['profiles']['client-profile']['tags'] = [
      {'name': 'escalated-to', 'description': 'Repeats a child relationship'},
    ];
    await saveConfig(taggedLikeRelationship);
    await expectLater(
      WayfinderProfileResolver(dataDirectory: data).resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          'Profile client-profile: The project declares tag escalated-to, '
              'which equals a declared relationship name.',
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

    Future<void> configure(String ref) => saveConfig({
      'version': 1,
      'profiles': {
        'bitwild-profile': {
          'source': {
            'git': source.path,
            'ref': 'v2026.3',
            'path': 'profiles/bitwild',
          },
          'applies_to': <String>[],
        },
        'client-profile': {
          'extends': 'bitwild-profile',
          'source': {'git': source.path, 'ref': ref, 'path': 'child'},
          'applies_to': ['./knowledge'],
          'actors': {
            'process:fixture': {'name': 'Fixture process'},
          },
          'tags': [
            {'name': 'governance', 'description': 'Governance topic'},
          ],
        },
      },
    });

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
      expect(resolved.effective[_bitwild]!.chain.map((package) => package.id), [
        _bitwild,
      ]);
      final composed = resolved.effective[_client]!;
      expect(composed.chain.map((package) => package.id), [_bitwild, _client]);
      expect(
        composed.selected.rules.single.descriptor.id,
        'client-profile/type-allowed',
      );
      final lock =
          jsonDecode(
                await File(
                  p.join(project.path, 'wayfinder.lock'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(
        (lock['profiles']['client-profile'] as Map).keys,
        unorderedEquals([
          'source',
          'requested_ref',
          'resolved_commit',
          'path',
          'profile_release',
        ]),
      );

      expect(await cli.run(['validate', bundle, '--output=json']), 1);
      final report = jsonDecode(output.single) as Map<String, dynamic>;
      final profile = report['profile'] as Map<String, dynamic>;
      expect(profile['state'], 'FAIL');
      expect(profile['release'], '2026.3');
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
        final base = await _gitOutput(source.path, [
          'rev-parse',
          'v2026.3^{commit}',
        ]);
        await lockFile.writeAsString(
          jsonEncode({
            'lock_version': 1,
            'configuration_sha256':
                WayfinderProfileResolver.canonicalConfigurationSha256(raw),
            'profiles': {
              'bitwild-profile': {
                'source': source.path,
                'requested_ref': 'v2026.3',
                'resolved_commit': base,
                'path': 'profiles/bitwild',
                'profile_release': '2026.3',
              },
              'client-profile': {
                'source': source.path,
                'requested_ref': 'child-bad',
                'resolved_commit': bad,
                'path': 'child',
                'profile_release': '2026.3',
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
    expect(output, contains('Profile 2026.3: PASS'));
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
    expect(resolved.effective.keys, [acmeId]);
    expect(resolved.effective[acmeId]!.chain.map((package) => package.id), [
      acmeId,
    ]);
    final lock =
        jsonDecode(
              await File(p.join(project.path, 'wayfinder.lock')).readAsString(),
            )
            as Map<String, dynamic>;
    expect((lock['profiles'] as Map).keys, ['acme-notes']);
    expect(lock['profiles']['acme-notes']['profile_release'], '1.0');

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
    expect(jsonDecode(output.single), containsPair('direct', true));
    output.clear();
    expect(await cli.run(['upgrade', project.path, '--output=json']), 0);
    expect(jsonDecode(output.single), containsPair('upgraded', true));
    expect(errors, isEmpty);
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
