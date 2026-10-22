import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

final _bitwild = ProfileId.parse('bitwild-profile');

void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late Directory data;
  late List<List<String>> calls;
  late WayfinderProfileResolver resolver;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-plan-');
    (:source, :project, :data) = await bitwildProject(temp);
    calls = [];
    resolver = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, cancel}) {
        calls.add(arguments);
        return runGit(
          arguments,
          workingDirectory: workingDirectory,
          cancel: cancel,
        );
      },
    );
  });

  tearDown(() => temp.delete(recursive: true));

  File lockFile() => File(p.join(project.path, 'wayfinder.lock'));
  String bundle() => p.join(project.path, 'knowledge');

  Matcher failsWith(String code) => throwsA(
    isA<WayfinderException>().having((error) => error.code, 'code', code),
  );

  Future<File> projectLock() async {
    final root = await project.resolveSymbolicLinks();
    return File(
      p.join(
        data.path,
        'projects',
        '${sha256.convert(utf8.encode(root))}.get.lock',
      ),
    );
  }

  File mirrorLock() => File(
    p.join(
      data.path,
      'profiles',
      '${sha256.convert(utf8.encode(source.path))}.lock',
    ),
  );

  test('plan writes nothing in the project; apply writes what it '
      'planned', () async {
    final before = await fileSnapshot(project.path);
    final plan = await resolver.plan(project.path);
    expect(await fileSnapshot(project.path), before);
    expect(await lockFile().exists(), isFalse);
    expect(plan.lockChanged, isTrue);
    expect(plan.fetched, isTrue);
    expect(plan.fetches.map((fetch) => (fetch.kind, fetch.git, fetch.ref)), [
      (ProfileFetchKind.clone, source.path, 'v2026.3'),
    ]);
    expect(plan.toJson()['fetches'], [
      {
        'kind': 'clone',
        'git': source.path,
        'location': source.path,
        'ref': 'v2026.3',
      },
    ]);
    expect(plan.packages.keys, [_bitwild]);
    expect(plan.toJson()['skills'], [
      {
        'id': 'bitwild-profile',
        'directories': [
          '.claude/skills/bitwild-profile',
          '.agents/skills/bitwild-profile',
        ],
        'written': true,
      },
    ]);
    expect(plan.removedSkills, isEmpty);
    expect(plan.toJson(), containsPair('lock_changed', true));
    expect(await Directory(p.join(project.path, '.claude')).exists(), isFalse);

    final result = await resolver.apply(plan);
    expect(result.reused, isFalse);
    expect(result.packages, plan.packages);
    expect(await lockFile().exists(), isTrue);
    expect(
      await File(
        p.join(
          project.path,
          '.claude',
          'skills',
          'bitwild-profile',
          'SKILL.md',
        ),
      ).exists(),
      isTrue,
    );
    expect(
      await validateWithProfileSources(bundle(), resolver: resolver),
      isA<ProfileValidationResult>().having(
        (result) => result.profileId,
        'profileId',
        _bitwild,
      ),
    );
  });

  test('a converged project plans no change and applies as reused', () async {
    await resolver.resolve(project.path);
    final lock = await lockFile().readAsBytes();
    calls.clear();
    final plan = await resolver.plan(project.path);
    expect(plan.lockChanged, isFalse);
    expect(plan.fetched, isFalse);
    expect(plan.fetches, isEmpty);
    expect(calls.map((call) => call.first), isNot(contains('clone')));
    final result = await resolver.apply(plan);
    expect(result.reused, isTrue);
    expect(await lockFile().readAsBytes(), lock);
  });

  test('a fetch policy decides each fetch before it runs', () async {
    final asked = <ProfileFetch>[];
    await expectLater(
      resolver.plan(
        project.path,
        allowFetch: (fetch) {
          asked.add(fetch);
          return false;
        },
      ),
      throwsA(
        isA<ProfileFetchRequiredException>()
            .having((error) => error.code, 'code', 'fetch-required')
            .having(
              (error) =>
                  (error.fetch.kind, error.fetch.location, error.fetch.ref),
              'fetch',
              (ProfileFetchKind.clone, source.path, 'v2026.3'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('that fetch was not allowed'),
            ),
      ),
    );
    expect(asked.map((fetch) => fetch.location), [source.path]);
    expect(calls.map((call) => call.first), isNot(contains('clone')));
    await expectLater(
      resolver.resolve(project.path, allowFetch: (_) => false),
      failsWith('fetch-required'),
    );
    expect(await lockFile().exists(), isFalse);

    final plan = await resolver.plan(
      project.path,
      allowFetch: (fetch) => fetch.location == source.path,
    );
    expect(plan.fetches.map((fetch) => fetch.kind), [ProfileFetchKind.clone]);
  });

  test('select runs no Git command at all', () async {
    await resolver.resolve(project.path);
    final selecting = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, cancel}) =>
          fail('select ran git ${arguments.join(' ')}'),
    );
    final selection = await selecting.select(bundle());
    expect(selection, isA<SelectedProfile>());
    final validation = await validateWithProfileSources(
      bundle(),
      resolver: selecting,
    );
    expect(validation.profileId, _bitwild);
  });

  test('every Git command of a plan runs under the mirror lock', () async {
    final unlocked = <String>[];
    final locking = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, cancel}) async {
        if (!await WayfinderFileLock.isHeld(mirrorLock())) {
          unlocked.add(arguments.join(' '));
        }
        calls.add(arguments);
        return runGit(
          arguments,
          workingDirectory: workingDirectory,
          cancel: cancel,
        );
      },
    );
    await locking.resolve(project.path);
    expect(calls.map((call) => call.first), containsAll(['clone', 'show']));
    expect(calls.map((call) => call.first), contains('ls-tree'));
    expect(unlocked, isEmpty);
    expect(await WayfinderFileLock.isHeld(mirrorLock()), isFalse);
  });

  group('a cache an earlier Wayfinder wrote', () {
    Future<void> dropPackageFiles() async {
      await resolver.resolve(project.path);
      await Directory(
        p.join(data.path, 'profiles', 'packages'),
      ).delete(recursive: true);
      calls.clear();
    }

    test('select reports it without running Git', () async {
      await dropPackageFiles();
      final selection = await resolver.select(bundle());
      expect(
        selection,
        isA<UnselectedProfile>().having(
          (selection) => selection.reasons.single.message,
          'message',
          contains('as in a cache an earlier Wayfinder wrote'),
        ),
      );
      expect(calls, isEmpty);
    });

    test('validation restores it from the mirror without fetching', () async {
      await dropPackageFiles();
      final validation = await validateWithProfileSources(
        bundle(),
        resolver: resolver,
      );
      expect(validation.profileId, _bitwild);
      expect(calls, [
        [
          'show',
          '${await _lockedCommit(lockFile())}:profiles/bitwild/'
              'wayfinder-profile.json',
        ],
      ]);
      calls.clear();
      expect(await resolver.select(bundle()), isA<SelectedProfile>());
      expect(
        await validateWithProfileSources(bundle(), resolver: resolver),
        isA<ProfileValidationResult>().having(
          (result) => result.profileId,
          'profileId',
          _bitwild,
        ),
      );
      expect(calls, isEmpty);
    });

    test('restoring skips a mirror another process holds', () async {
      await dropPackageFiles();
      final held = (await WayfinderFileLock.tryExclusive(mirrorLock()))!;
      try {
        expect(await resolver.restoreCachedPackages(bundle()), 0);
        expect(
          (await validateWithProfileSources(
            bundle(),
            resolver: resolver,
          )).profileId,
          isNull,
        );
      } finally {
        await held.release();
      }
      expect(calls, isEmpty);
      expect(await resolver.restoreCachedPackages(bundle()), 1);
    });

    test('restoring needs a current lock', () async {
      await dropPackageFiles();
      final config = File(p.join(project.path, 'wayfinder.json'));
      final value = jsonDecode(await config.readAsString()) as Map;
      ((value['profiles'] as Map)['bitwild-profile'] as Map)['tags'] = [
        {'name': 'billing', 'description': 'Billing topic'},
      ];
      await config.writeAsString(jsonEncode(value));
      expect(await resolver.restoreCachedPackages(bundle()), 0);
      final selection = await resolver.select(bundle());
      expect(
        (selection as UnselectedProfile).reasons.single.message,
        startsWith('Profile lock is stale'),
      );
      expect(calls, isEmpty);
    });
  });

  group('apply refuses a plan whose inputs changed', () {
    test('wayfinder.json', () async {
      final plan = await resolver.plan(project.path);
      final config = File(p.join(project.path, 'wayfinder.json'));
      await config.writeAsString('${await config.readAsString()}\n');
      await expectLater(resolver.apply(plan), failsWith('resolution-stale'));
      expect(await lockFile().exists(), isFalse);
    });

    test('wayfinder.lock', () async {
      await resolver.resolve(project.path);
      final plan = await resolver.plan(project.path, upgrade: true);
      final locked = await lockFile().readAsString();
      await lockFile().writeAsString('$locked\n');
      await expectLater(resolver.apply(plan), failsWith('resolution-stale'));
      expect(await lockFile().readAsString(), '$locked\n');
    });

    test('a package file in the Profile cache', () async {
      final plan = await resolver.plan(project.path);
      await Directory(
        p.join(data.path, 'profiles', 'packages'),
      ).delete(recursive: true);
      await expectLater(resolver.apply(plan), failsWith('resolution-stale'));
      expect(await lockFile().exists(), isFalse);
    });
  });

  test('another get on the project is resolution-busy, and the lock '
      'records its project', () async {
    final plan = await resolver.plan(project.path);
    final held = (await WayfinderFileLock.tryExclusive(await projectLock()))!;
    try {
      await expectLater(
        resolver.apply(plan),
        throwsA(
          isA<ProfileResolutionBusyException>()
              .having((error) => error.code, 'code', 'resolution-busy')
              .having((error) => error.projectRoot, 'projectRoot', project.path)
              .having((error) => error.source, 'source', isNull)
              .having(
                (error) => error.message,
                'message',
                'Another Profile resolution is changing ${project.path}. '
                    'Retry when it finishes.',
              ),
        ),
      );
      await expectLater(
        resolver.resolve(project.path),
        failsWith('resolution-busy'),
      );
    } finally {
      await held.release();
    }
    expect(await lockFile().exists(), isFalse);
    await resolver.apply(plan);
    expect(jsonDecode(await (await projectLock()).readAsString()), {
      'root': await project.resolveSymbolicLinks(),
    });
    expect(await WayfinderFileLock.isHeld(await projectLock()), isFalse);
  });

  test('a get in another isolate excludes this one', () async {
    final lockPath = (await projectLock()).path;
    final ready = ReceivePort();
    final readySends = ready.sendPort;
    final worker = Isolate.run(() async {
      final lock = (await WayfinderFileLock.tryExclusive(File(lockPath)))!;
      final control = ReceivePort();
      readySends.send(control.sendPort);
      await control.first;
      await lock.release();
    });
    final control = await ready.first as SendPort;
    try {
      await expectLater(
        resolver.resolve(project.path),
        failsWith('resolution-busy'),
      );
    } finally {
      control.send(null);
      await worker;
    }
    expect((await resolver.resolve(project.path)).reused, isFalse);
  });

  test('plan waits while another holds the Profile source mirror', () async {
    await mirrorLock().parent.create(recursive: true);
    final held = (await WayfinderFileLock.tryExclusive(mirrorLock()))!;
    var planned = false;
    final planning = resolver.plan(project.path).then((plan) {
      planned = true;
      return plan;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(planned, isFalse);
    expect(calls, isEmpty);
    await held.release();
    expect((await planning).packages.keys, [_bitwild]);
  });

  test('a cancelled plan stops before running Git', () async {
    final cancel = WayfinderCancellationController()..cancel();
    await expectLater(
      resolver.plan(project.path, cancel: cancel),
      failsWith('cancelled'),
    );
    expect(calls, isEmpty);
  });

  test('cancelling while the mirror is busy stops the plan', () async {
    await mirrorLock().parent.create(recursive: true);
    final held = (await WayfinderFileLock.tryExclusive(mirrorLock()))!;
    final cancel = WayfinderCancellationController();
    try {
      final planning = resolver.plan(project.path, cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();
      await expectLater(planning, failsWith('cancelled'));
    } finally {
      await held.release();
    }
    expect(calls, isEmpty);
  });

  test('a cancelled Git command fails the plan with cancelled', () async {
    final cancel = WayfinderCancellationController();
    final cancelling = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, cancel}) {
        (cancel! as WayfinderCancellationController).cancel();
        return runGit(
          arguments,
          workingDirectory: workingDirectory,
          cancel: cancel,
        );
      },
    );
    await expectLater(
      cancelling.plan(project.path, cancel: cancel),
      failsWith('cancelled'),
    );
    expect(await lockFile().exists(), isFalse);
  });
  group('a locked-only plan', () {
    late String locked;
    late List<int> lockBytes;

    setUp(() async {
      await resolver.resolve(project.path);
      locked = await _lockedCommit(lockFile());
      lockBytes = await lockFile().readAsBytes();
      calls.clear();
    });

    /// Commits again in the source and moves `v2026.3` to it, so a plan
    /// that resolved the ref would see another commit; the locked one stays
    /// reachable from the branch.
    Future<String> moveTag() async {
      await File(p.join(source.path, 'revision.txt')).writeAsString('moved');
      await fixtureGit(source.path, ['add', '.']);
      await fixtureGit(source.path, ['commit', '-q', '-m', 'Move']);
      await fixtureGit(source.path, ['tag', '-f', 'v2026.3']);
      return fixtureGit(source.path, ['rev-parse', 'HEAD']);
    }

    test('fetches exactly the locked commits onto a machine without them, '
        'and leaves the lock', () async {
      await moveTag();
      await data.delete(recursive: true);
      final asked = <ProfileFetch>[];
      final plan = await resolver.plan(
        project.path,
        lockedOnly: true,
        allowFetch: (fetch) {
          asked.add(fetch);
          return true;
        },
      );
      expect(plan.lockedOnly, isTrue);
      expect(plan.toJson(), containsPair('locked_only', true));
      expect(plan.lockChanged, isFalse);
      expect(plan.packages[_bitwild]!.commit, locked);
      expect(asked.map((fetch) => (fetch.kind, fetch.location)), [
        (ProfileFetchKind.clone, source.path),
      ]);
      // The only command that reached the network cloned the locked source,
      // and every read named the locked commit; no ref was resolved.
      expect(calls.where(gitMayReachRemote).map((call) => call.first), [
        'clone',
      ]);
      expect(calls, anyElement(equals(['cat-file', '-e', '$locked^{commit}'])));
      expect(calls.where((call) => call.first == 'rev-parse'), isEmpty);
      expect(
        calls.where((call) => call.first == 'show').map((call) => call[1]),
        everyElement(startsWith('$locked:')),
      );
      await resolver.apply(plan);
      expect(await lockFile().readAsBytes(), lockBytes);
      calls.clear();
      expect(await resolver.select(bundle()), isA<SelectedProfile>());
      expect(calls, isEmpty);
    });

    test('refreshes a mirror that lacks the locked commit, and resolves '
        'that commit', () async {
      final moved = await moveTag();
      final lock = jsonDecode(await lockFile().readAsString()) as Map;
      ((lock['packages'] as Map)['bitwild-profile'] as Map)['resolved_commit'] =
          moved;
      await lockFile().writeAsString(jsonEncode(lock));
      final asked = <ProfileFetch>[];
      final plan = await resolver.plan(
        project.path,
        lockedOnly: true,
        allowFetch: (fetch) {
          asked.add(fetch);
          return true;
        },
      );
      expect(plan.packages[_bitwild]!.commit, moved);
      expect(asked.map((fetch) => (fetch.kind, fetch.location)), [
        (ProfileFetchKind.refresh, source.path),
      ]);
      expect(calls.where(gitMayReachRemote).map((call) => call.first), [
        'remote',
      ]);
      expect(calls.where((call) => call.first == 'rev-parse'), isEmpty);
    });

    test('runs no Git command and fetches nothing when the lock as written '
        'would change', () async {
      await data.delete(recursive: true);
      Future<void> refused(
        ProfileBindingState state,
        String reason,
        Map<String, Object?> change,
      ) async {
        calls.clear();
        await expectLater(
          resolver.plan(project.path, lockedOnly: true),
          throwsA(
            isA<ProfileLockChangeRequiredException>()
                .having((error) => error.code, 'code', 'lock-change-required')
                .having((error) => error.state, 'state', state)
                .having(
                  (error) => error.message,
                  'message',
                  'Resolving would change wayfinder.lock, which a '
                      'locked-only plan never does: $reason',
                )
                .having((error) => error.change.toJson(), 'change', {
                  'reason': reason,
                  ...change,
                })
                .having(
                  (error) => error.profile?.value,
                  'profile',
                  change['profile'],
                ),
          ),
        );
        expect(calls, isEmpty);
        expect(await data.exists(), isFalse, reason: 'nothing was fetched');
        // The status says the same offline, and the binding's own status
        // says it too when the binding is the reason.
        final status = await resolver.status(project.path);
        expect(status.lockChange?.toJson(), {'reason': reason, ...change});
        if (change['kind'] != 'packages-unreached') {
          expect(status.of(_bitwild)!.state, state);
          expect(status.of(_bitwild)!.lockChange?.toJson(), {
            'reason': reason,
            ...change,
          });
        }
      }

      Future<void> writeLock(
        Map<String, Object?> Function(Map<String, Object?> lock) edit,
      ) => lockFile().writeAsString(
        jsonEncode(
          edit(jsonDecode(utf8.decode(lockBytes)) as Map<String, Object?>),
        ),
      );
      Map<String, Object?> packagesOf(Map<String, Object?> lock) =>
          lock['packages']! as Map<String, Object?>;
      Map<String, Object?> bitwildOf(Map<String, Object?> lock) =>
          packagesOf(lock)['bitwild-profile']! as Map<String, Object?>;

      await lockFile().delete();
      await refused(
        ProfileBindingState.lockMissing,
        'Profile lock is missing or unreadable.',
        {'kind': 'lock-missing', 'profile': null, 'packages': <Object?>[]},
      );

      await writeLock((lock) => {...lock, 'configuration_sha256': '0' * 64});
      await refused(
        ProfileBindingState.lockStale,
        'Profile lock is stale: the configuration changed after the lock was '
        'written.',
        {
          'kind': 'configuration-changed',
          'profile': null,
          'packages': <Object?>[],
        },
      );

      await writeLock(
        (lock) => {
          ...lock,
          'packages': {
            'bitwild-profile': {...bitwildOf(lock), 'requested_ref': 'main'},
          },
        },
      );
      await refused(
        ProfileBindingState.lockStale,
        'Profile lock records bitwild-profile from ${source.path} at main '
        '(profiles/bitwild); the configuration names ${source.path} at '
        'v2026.3 (profiles/bitwild).',
        {
          'kind': 'source-changed',
          'profile': 'bitwild-profile',
          'packages': ['bitwild-profile'],
        },
      );

      await writeLock(
        (lock) => {
          ...lock,
          'packages': {
            ...packagesOf(lock),
            'stray-profile': {...bitwildOf(lock), 'path': 'stray'},
          },
        },
      );
      await refused(
        ProfileBindingState.lockStale,
        'Profile lock records stray-profile, which no configured chain '
        'reaches.',
        {
          'kind': 'packages-unreached',
          'profile': null,
          'packages': ['stray-profile'],
        },
      );
    });

    test('refuses once read a package that disagrees with the lock it was '
        'locked from', () async {
      final lock = jsonDecode(await lockFile().readAsString()) as Map;
      ((lock['packages'] as Map)['bitwild-profile'] as Map)['release'] =
          '2026.9';
      await lockFile().writeAsString(jsonEncode(lock));
      await expectLater(
        resolver.plan(project.path, lockedOnly: true),
        throwsA(
          isA<ProfileLockChangeRequiredException>()
              .having(
                (error) => error.state,
                'state',
                ProfileBindingState.lockStale,
              )
              .having(
                (error) => error.change.kind,
                'kind',
                ProfileLockChangeKind.packageChanged,
              )
              .having((error) => error.change.packages, 'packages', [_bitwild])
              .having(
                (error) => error.change.reason,
                'reason',
                'Profile bitwild-profile declares another release or parent '
                    'than the lock records.',
              ),
        ),
      );
      expect(calls.where(gitMayReachRemote), isEmpty);
    });

    test('keeps a lock that reads the same in other bytes', () async {
      await lockFile().writeAsString(
        jsonEncode(jsonDecode(utf8.decode(lockBytes))),
      );
      final compact = await lockFile().readAsBytes();
      final plan = await resolver.plan(project.path, lockedOnly: true);
      expect(plan.lockChanged, isFalse);
      await resolver.apply(plan);
      expect(await lockFile().readAsBytes(), compact);
      expect((await resolver.plan(project.path)).lockChanged, isTrue);
    });

    test('reinstalls the locked skills offline', () async {
      final skill = Directory(
        p.join(project.path, '.claude', 'skills', 'bitwild-profile'),
      );
      await skill.delete(recursive: true);
      final plan = await resolver.plan(
        project.path,
        lockedOnly: true,
        allowFetch: (_) => false,
      );
      expect(plan.fetched, isFalse);
      expect(plan.skills.single.written, isTrue);
      await resolver.apply(plan);
      expect(await File(p.join(skill.path, 'SKILL.md')).exists(), isTrue);
      expect(await lockFile().readAsBytes(), lockBytes);
    });

    test('does not upgrade', () {
      expect(
        () => resolver.plan(project.path, upgrade: true, lockedOnly: true),
        throwsArgumentError,
      );
    });

    group('that leaves skills alone', () {
      Directory skill(String root) =>
          Directory(p.join(project.path, root, 'skills', 'bitwild-profile'));
      Map<String, Object?> revision(String commit) => {
        'release': '2026.3',
        'commit': commit,
      };
      bool readsSkillFiles(List<String> call) =>
          call.first == 'ls-tree' ||
          (call.first == 'cat-file' && call.contains('blob'));

      late File stray;

      setUp(() async {
        // A directory the user owns where the Profile skill goes, one marked
        // with another commit, and a marked skill of a Profile no longer
        // locked, which get would prune.
        await File(
          p.join(skill('.claude').path, '.wayfinder-profile'),
        ).delete();
        await File(
          p.join(skill('.claude').path, 'NOTES.md'),
        ).writeAsString('mine\n');
        await File(
          p.join(skill('.agents').path, '.wayfinder-profile'),
        ).writeAsString(
          ProfileSkills.markerText((
            id: _bitwild,
            release: '2026.3',
            commit: '0' * 40,
          )),
        );
        final retired = await Directory(
          p.join(project.path, '.claude', 'skills', 'retired-profile'),
        ).create(recursive: true);
        stray = File(p.join(retired.path, '.wayfinder-profile'));
        await stray.writeAsString(
          ProfileSkills.markerText((
            id: ProfileId.parse('retired-profile'),
            release: '1',
            commit: 'a' * 40,
          )),
        );
        await data.delete(recursive: true);
      });

      test('fills the cache, writes no skill directory, and reports each '
          "one's state", () async {
        final before = await fileSnapshot(project.path);
        final plan = await resolver.plan(
          project.path,
          lockedOnly: true,
          skills: false,
        );
        expect(plan.includesSkills, isFalse);
        expect(plan.toJson(), containsPair('includes_skills', false));
        expect(plan.fetches.map((fetch) => fetch.kind), [
          ProfileFetchKind.clone,
        ]);
        expect(plan.skills.single.written, isFalse);
        expect(plan.removedSkills, isEmpty);
        expect(plan.toJson()['skill_directories'], [
          {
            'profile': 'bitwild-profile',
            'root': '.claude/skills',
            'path': '.claude/skills/bitwild-profile',
            'state': 'unmarked',
            'installed': null,
          },
          {
            'profile': 'bitwild-profile',
            'root': '.agents/skills',
            'path': '.agents/skills/bitwild-profile',
            'state': 'stale',
            'installed': revision('0' * 40),
          },
        ]);
        expect(calls.where(readsSkillFiles), isEmpty);
        expect(await fileSnapshot(project.path), before);

        final result = await resolver.apply(plan);
        expect(result.skills.single.written, isFalse);
        expect(result.removedSkills, isEmpty);
        expect(await fileSnapshot(project.path), before);
        expect(await stray.exists(), isTrue);
        expect(calls.where(readsSkillFiles), isEmpty);

        // The cache now holds the locked package, so selection works
        // offline and the status names the skill directories as data.
        calls.clear();
        final status = (await resolver.status(project.path)).of(_bitwild)!;
        expect(calls, isEmpty);
        expect(status.state, ProfileBindingState.resolved);
        expect(status.copies.single.toJson(), {
          'id': 'bitwild-profile',
          'location': source.path,
          'has_mirror': true,
          'has_package': true,
        });
        expect(
          [
            for (final directory in status.skillDirectories)
              (directory.path, directory.state),
          ],
          [
            (
              '.claude/skills/bitwild-profile',
              ProfileSkillDirectoryState.unmarked,
            ),
            (
              '.agents/skills/bitwild-profile',
              ProfileSkillDirectoryState.stale,
            ),
          ],
        );
        expect(status.notes.single.code, DiagnosticCode.profileSkillStale);
      });

      test('reports a skill root outside the project that a plan with '
          'skills refuses', () async {
        final other = await Directory(
          p.join(temp.path, 'other', '.agents'),
        ).create(recursive: true);
        await Directory(
          p.join(project.path, '.agents'),
        ).delete(recursive: true);
        await Link(p.join(project.path, '.agents')).create(other.path);
        final before = await fileSnapshot(project.path);

        await expectLater(
          resolver.plan(project.path, lockedOnly: true),
          throwsA(
            isA<ProfileSkillDirectoriesException>()
                .having((error) => error.outsideRoots, 'outsideRoots', [
                  '.agents/skills',
                ])
                .having(
                  (error) => [
                    for (final directory in error.directories)
                      (directory.path, directory.state),
                  ],
                  'directories',
                  [
                    (
                      '.claude/skills/bitwild-profile',
                      ProfileSkillDirectoryState.unmarked,
                    ),
                    (
                      '.agents/skills/bitwild-profile',
                      ProfileSkillDirectoryState.outside,
                    ),
                  ],
                ),
          ),
        );
        final plan = await resolver.plan(
          project.path,
          lockedOnly: true,
          skills: false,
        );
        expect(
          [
            for (final directory in plan.skillDirectories)
              (directory.path, directory.state),
          ],
          [
            (
              '.claude/skills/bitwild-profile',
              ProfileSkillDirectoryState.unmarked,
            ),
            (
              '.agents/skills/bitwild-profile',
              ProfileSkillDirectoryState.outside,
            ),
          ],
        );
        await resolver.apply(plan);
        expect(await fileSnapshot(project.path), before);
        expect(await other.list().toList(), isEmpty);
      });

      test('a plan of the cache it filled installs the skills once they are '
          'free, offline', () async {
        await resolver.apply(
          await resolver.plan(project.path, lockedOnly: true, skills: false),
        );
        await skill('.claude').delete(recursive: true);
        calls.clear();
        final plan = await resolver.plan(
          project.path,
          lockedOnly: true,
          allowFetch: (_) => false,
        );
        expect(plan.includesSkills, isTrue);
        expect(plan.fetched, isFalse);
        expect(
          [
            for (final directory in plan.skillDirectories)
              (directory.path, directory.state),
          ],
          [
            (
              '.claude/skills/bitwild-profile',
              ProfileSkillDirectoryState.missing,
            ),
            (
              '.agents/skills/bitwild-profile',
              ProfileSkillDirectoryState.stale,
            ),
          ],
        );
        expect(plan.removedSkills, ['.claude/skills/retired-profile']);
        await resolver.apply(plan);
        expect(await stray.exists(), isFalse);
        expect(
          (await resolver.status(project.path)).of(_bitwild)!.notes,
          isEmpty,
        );
      });
    });
  });

  group('per-source consent', () {
    test('the source location rule', () {
      String locate(String git) =>
          WayfinderProfileSource.locationOf(git, projectRoot: '/work/app');
      expect(
        locate('https://example.test/p.git'),
        'https://example.test/p.git',
      );
      expect(
        locate('ssh://git@example.test/p.git'),
        'ssh://git@example.test/p.git',
      );
      expect(
        locate('git@example.test:org/p.git'),
        'git@example.test:org/p.git',
      );
      expect(locate('/srv/profiles'), '/srv/profiles');
      expect(locate(r'C:\profiles'), r'C:\profiles');
      expect(locate('../profiles'), p.normalize('/work/profiles'));
      expect(locate('./vendor/./p'), p.normalize('/work/app/vendor/p'));
    });

    test('a fetch policy hears of every Git command that can reach the '
        'network before it runs, at the location it reaches', () async {
      // A Profile in another repository, named by a relative path, extends
      // Bitwild from the source repository.
      final other = await Directory(p.join(temp.path, 'other')).create();
      await fixtureGit(other.path, ['init', '-q']);
      await fixtureGit(other.path, ['config', 'user.email', 't@example.test']);
      await fixtureGit(other.path, ['config', 'user.name', 'Wayfinder Test']);
      await Directory(p.join(other.path, 'child')).create();
      await File(
        p.join(other.path, 'child', 'wayfinder-profile.json'),
      ).writeAsString(
        jsonEncode({
          'format': 2,
          'id': 'client-profile',
          'release': '1.0',
          'implements': {'id': 'okf', 'release': '0.2'},
          'extends': {
            'git': source.path,
            'ref': 'v2026.3',
            'path': 'profiles/bitwild',
          },
          'rules': <Object?>[],
        }),
      );
      await fixtureGit(other.path, ['add', '.']);
      await fixtureGit(other.path, ['commit', '-q', '-m', 'Child']);
      await fixtureGit(other.path, ['tag', 'v1']);
      await File(p.join(project.path, 'wayfinder.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'profiles': {
            'client-profile': {
              'source': {'git': '../other', 'ref': 'v1', 'path': 'child'},
              'applies_to': ['./knowledge'],
            },
          },
        }),
      );
      final otherLocation = WayfinderProfileSource.locationOf(
        '../other',
        projectRoot: project.path,
      );
      expect(otherLocation, other.path);
      final byMirror = {
        for (final location in [otherLocation, source.path])
          p.join(
            data.path,
            'profiles',
            sha256.convert(utf8.encode(location)).toString(),
          ): location,
      };
      final allowed = <String>{};
      final unasked = <String>[];
      final remote = <String>[];
      final consenting = WayfinderProfileResolver(
        dataDirectory: data,
        git: (arguments, {workingDirectory, cancel}) {
          if (gitMayReachRemote(arguments)) {
            final location = arguments.first == 'clone'
                ? arguments[arguments.indexOf('--') + 1]
                : byMirror[workingDirectory]!;
            remote.add('${arguments.first} $location');
            if (!allowed.contains(location)) unasked.add(arguments.join(' '));
          }
          return runGit(
            arguments,
            workingDirectory: workingDirectory,
            cancel: cancel,
          );
        },
      );
      bool allow(ProfileFetch fetch) {
        expect(
          fetch.location,
          WayfinderProfileSource.locationOf(
            fetch.git,
            projectRoot: project.path,
          ),
        );
        allowed.add(fetch.location);
        return true;
      }

      final planned = await consenting.plan(project.path, allowFetch: allow);
      expect(planned.fetches.map((fetch) => (fetch.kind, fetch.location)), [
        (ProfileFetchKind.clone, other.path),
        (ProfileFetchKind.clone, source.path),
      ]);
      await consenting.apply(planned);
      allowed.clear();
      await consenting.plan(project.path, upgrade: true, allowFetch: allow);
      expect(remote, [
        'clone ${other.path}',
        'clone ${source.path}',
        'remote ${other.path}',
        'remote ${source.path}',
      ]);
      expect(unasked, isEmpty);

      // A policy that refuses the parent's source stops before its fetch.
      await data.delete(recursive: true);
      allowed.clear();
      remote.clear();
      await expectLater(
        consenting.plan(
          project.path,
          allowFetch: (fetch) => allow(fetch) && fetch.location == other.path,
        ),
        failsWith('fetch-required'),
      );
      expect(remote, ['clone ${other.path}']);
      expect(unasked, isEmpty);
    });
  });

  test('pruneProjectLocks deletes the get lock of a removed project once '
      'unused, and never a held one', () async {
    await resolver.resolve(project.path);
    final lock = await projectLock();
    expect(await lock.exists(), isTrue);
    expect(await resolver.pruneProjectLocks(unusedFor: Duration.zero), isEmpty);
    final moved = await project.rename('${project.path}-moved');
    await lock.setLastModified(
      DateTime.now().subtract(const Duration(days: 40)),
    );
    final holder = await WayfinderFileLock.tryExclusive(lock);
    expect(
      await resolver.pruneProjectLocks(),
      isEmpty,
      reason: 'a held lock is left, and its note is not read',
    );
    await holder!.release();
    await lock.setLastModified(
      DateTime.now().subtract(const Duration(days: 40)),
    );
    expect(
      await resolver.pruneProjectLocks(unusedFor: const Duration(days: 41)),
      isEmpty,
      reason: 'used within the period',
    );
    expect(await resolver.pruneProjectLocks(), [lock.path]);
    expect(await lock.exists(), isFalse);
    await moved.rename(project.path);
    expect(await resolver.pruneProjectLocks(), isEmpty);
  });
}

Future<String> _lockedCommit(File lock) async {
  final packages =
      (jsonDecode(await lock.readAsString()) as Map)['packages'] as Map;
  return (packages['bitwild-profile'] as Map)['resolved_commit'] as String;
}
