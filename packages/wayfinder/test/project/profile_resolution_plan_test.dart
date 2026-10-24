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
      await expectLater(resolver.apply(plan), failsWith('resolution-busy'));
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
