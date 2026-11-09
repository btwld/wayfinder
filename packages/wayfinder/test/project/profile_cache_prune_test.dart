import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart' show SelectedProfile;

import 'support.dart';

void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late Directory data;
  late WayfinderProfileResolver resolver;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-mirror-prune-');
    (:source, :project, :data) = await bitwildProject(temp);
    resolver = WayfinderProfileResolver(dataDirectory: data);
  });

  tearDown(() => temp.delete(recursive: true));

  String key(String location) =>
      sha256.convert(utf8.encode(location)).toString();
  Directory mirror([String? location]) =>
      Directory(p.join(data.path, 'profiles', key(location ?? source.path)));
  File metadata(Directory root) => File('${root.path}.metadata.json');

  Future<void> age(Directory root) async {
    final file = metadata(root);
    final value = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    value['last_used'] = DateTime.now()
        .subtract(const Duration(days: 31))
        .toUtc()
        .toIso8601String();
    await file.writeAsString(jsonEncode(value));
  }

  Future<Directory> legacy(String location) async {
    final root = mirror(location);
    await root.create(recursive: true);
    await fixtureGit(root.path, ['init', '--bare', '-q']);
    await fixtureGit(root.path, ['config', 'remote.origin.url', location]);
    return root;
  }

  test('missing local sources make mirrors eligible', () async {
    await resolver.resolve(project.path);
    await source.delete(recursive: true);
    final result = await resolver.pruneMirrors();
    expect(result.removed.map((entry) => entry.path), [mirror().path]);
    expect(
      result.removed.single.reason,
      ProfileMirrorPruneReason.missingSource,
    );
    expect(result.errors, isEmpty);
    expect(await mirror().exists(), isFalse);
    // Keep the sibling lock inode for planners which already opened it.
    expect(await File('${mirror().path}.lock').exists(), isTrue);
    expect(await metadata(mirror()).exists(), isFalse);
    // The package snapshot still supports ordinary offline selection.
    expect(
      await resolver.select(p.join(project.path, 'knowledge')),
      isA<SelectedProfile>(),
    );
  });

  test('held mirrors and newly used mirrors survive prune', () async {
    await resolver.resolve(project.path);
    await age(mirror());
    final held = await WayfinderFileLock.exclusive(
      File('${mirror().path}.lock'),
    );
    try {
      final result = await resolver.pruneMirrors();
      expect(result.busy, [mirror().path]);
      expect(result.removed, isEmpty);
    } finally {
      await held.release();
    }
    await resolver.plan(project.path);
    expect((await resolver.pruneMirrors()).removed, isEmpty);
    await age(mirror());
    expect(
      (await resolver.pruneMirrors(
        unusedFor: const Duration(days: 60),
      )).removed,
      isEmpty,
    );
    expect((await resolver.pruneMirrors()).removed, hasLength(1));
  });

  test('legacy remote mirrors receive an observation grace period', () async {
    final root = await legacy('https://example.test/profiles.git');
    final first = await resolver.pruneMirrors();
    expect(first.removed, isEmpty);
    final value = jsonDecode(await metadata(root).readAsString()) as Map;
    expect(value['version'], 1);
    expect(value['last_used'], isNull);
    expect(value['observed_at'], isA<String>());
    value['observed_at'] = DateTime.now()
        .subtract(const Duration(days: 31))
        .toUtc()
        .toIso8601String();
    await metadata(root).writeAsString(jsonEncode(value));
    final second = await resolver.pruneMirrors();
    expect(second.removed.single.path, root.path);
    expect(second.removed.single.reason, ProfileMirrorPruneReason.unused);
  });

  test('a legacy missing source is eligible without a grace period', () async {
    final root = await legacy(p.join(temp.path, 'removed', 'source'));
    expect((await resolver.pruneMirrors()).removed.single.path, root.path);
  });

  test(
    'a removed source worktree is eligible while its repository survives',
    () async {
      final worktree = Directory(p.join(temp.path, 'source-worktree'));
      await fixtureGit(source.path, [
        'worktree',
        'add',
        '--detach',
        worktree.path,
        'v2026.3',
      ]);
      final config = File(p.join(project.path, 'wayfinder.json'));
      await config.writeAsString(
        (await config.readAsString()).replaceAll(source.path, worktree.path),
      );
      await resolver.resolve(project.path);
      await fixtureGit(source.path, ['worktree', 'remove', worktree.path]);
      final result = await resolver.pruneMirrors();
      expect(result.removed.single.path, mirror(worktree.path).path);
      expect(
        result.removed.single.reason,
        ProfileMirrorPruneReason.missingSource,
      );
      expect(await source.exists(), isTrue);
    },
  );

  test('legacy inspection never discovers an enclosing repository', () async {
    final origin = p.join(temp.path, 'gone');
    await fixtureGit(source.path, ['config', 'remote.origin.url', origin]);
    final nestedData = Directory(p.join(source.path, 'cache'));
    final unknown = await Directory(
      p.join(nestedData.path, 'profiles', key(origin)),
    ).create(recursive: true);
    await File(p.join(unknown.path, 'keep')).writeAsString('keep');
    final nested = WayfinderProfileResolver(dataDirectory: nestedData);
    final result = await nested.pruneMirrors();
    expect(result.removed, isEmpty);
    expect(result.errors, hasLength(1));
    expect(await unknown.exists(), isTrue);
  });

  test('restore records mirror use; package-only selection does not', () async {
    await resolver.resolve(project.path);
    await age(mirror());
    final before = await metadata(mirror()).readAsString();
    await resolver.select(p.join(project.path, 'knowledge'));
    expect(await metadata(mirror()).readAsString(), before);
    final packages = Directory(p.join(data.path, 'profiles', 'packages'));
    await packages.delete(recursive: true);
    expect(
      await resolver.restoreCachedPackages(p.join(project.path, 'knowledge')),
      1,
    );
    expect(await metadata(mirror()).readAsString(), isNot(before));
    expect((await resolver.pruneMirrors()).removed, isEmpty);
  });

  test('dry-run changes no files or timestamps', () async {
    await resolver.resolve(project.path);
    await age(mirror());
    await legacy('https://example.test/legacy.git');
    // The legacy entry has no sibling lock. Dry-run must not create one.
    final before = await fileSnapshot(data.path);
    final times = await _modifiedTimes(data);
    final result = await resolver.pruneMirrors(dryRun: true);
    expect(result.candidates.map((entry) => entry.path), [mirror().path]);
    expect(result.removed, isEmpty);
    expect(result.errors, isEmpty);
    expect(await fileSnapshot(data.path), before);
    expect(await _modifiedTimes(data), times);
    expect((await resolver.pruneMirrors()).removed.single.path, mirror().path);
  });

  test(
    'dry-run lists a legacy missing source without creating its lock',
    () async {
      final root = await legacy(p.join(temp.path, 'gone'));
      final before = await fileSnapshot(data.path);
      final times = await _modifiedTimes(data);
      final result = await resolver.pruneMirrors(dryRun: true);
      expect(result.candidates.single.path, root.path);
      expect(result.removed, isEmpty);
      expect(await fileSnapshot(data.path), before);
      expect(await _modifiedTimes(data), times);
      expect(await File('${root.path}.lock').exists(), isFalse);
    },
  );

  test('package snapshots and symlink targets survive prune', () async {
    await resolver.resolve(project.path);
    await age(mirror());
    final packages = Directory(p.join(data.path, 'profiles', 'packages'));
    final snapshots = await fileSnapshot(packages.path);
    final target = await Directory(p.join(temp.path, 'target')).create();
    await File(p.join(target.path, 'keep')).writeAsString('keep');
    await Link(p.join(data.path, 'profiles', 'a' * 64)).create(target.path);
    await Link(p.join(mirror().path, 'linked')).create(target.path);
    final result = await resolver.pruneMirrors();
    expect(result.removed, hasLength(1));
    expect(await fileSnapshot(packages.path), snapshots);
    expect(await File(p.join(target.path, 'keep')).readAsString(), 'keep');
    expect(
      await Link(p.join(data.path, 'profiles', 'a' * 64)).exists(),
      isTrue,
    );
  });

  test('unknown metadata and origin lookup errors preserve mirrors', () async {
    await resolver.resolve(project.path);
    await metadata(mirror()).writeAsString('{"version":999}');
    final broken = await Directory(
      p.join(data.path, 'profiles', 'b' * 64),
    ).create();
    final result = await resolver.pruneMirrors(unusedFor: Duration.zero);
    expect(result.removed, isEmpty);
    expect(result.errors, hasLength(2));
    expect(await mirror().exists(), isTrue);
    expect(await broken.exists(), isTrue);
  });

  test(
    'foreign Windows paths are not mistaken for missing local sources',
    () async {
      if (Platform.isWindows) return;
      final root = await legacy(r'C:\removed\source');
      final unc = await legacy(r'\\server\share\source');
      final slashUnc = await legacy('//server/share/source');
      expect((await resolver.pruneMirrors()).removed, isEmpty);
      expect(await root.exists(), isTrue);
      expect(await unc.exists(), isTrue);
      expect(await slashUnc.exists(), isTrue);
    },
  );

  test('collectors in different isolates use the same mirror lock', () async {
    final root = await legacy('https://example.test/concurrent.git');
    final inspecting = Completer<void>();
    final proceed = Completer<void>();
    final first = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, cancel}) async {
        inspecting.complete();
        await proceed.future;
        return runGit(
          arguments,
          workingDirectory: workingDirectory,
          cancel: cancel,
        );
      },
    ).pruneMirrors();
    await inspecting.future;
    try {
      final dataPath = data.path;
      final busy = await _busyInOtherIsolate(dataPath);
      expect(busy, [root.path]);
    } finally {
      proceed.complete();
      expect((await first).errors, isEmpty);
    }
  });

  test('only old owned clone staging directories are collected', () async {
    await resolver.resolve(project.path);
    final old = DateTime.now().subtract(const Duration(days: 31)).toUtc();
    Future<Directory> staging(DateTime created, {bool owned = true}) async {
      final root = await Directory(
        '${mirror().path}.tmp-321-${created.microsecondsSinceEpoch}',
      ).create();
      await File(p.join(root.path, 'partial')).writeAsString('partial clone');
      if (owned) {
        await metadata(root).writeAsString(
          jsonEncode({
            'version': 1,
            'mirror': key(source.path),
            'created_at': created.toIso8601String(),
          }),
        );
      }
      return root;
    }

    final owned = await staging(old);
    final unowned = await staging(
      old.subtract(const Duration(seconds: 1)),
      owned: false,
    );
    final recent = await staging(DateTime.now().toUtc());
    final held = await WayfinderFileLock.exclusive(
      File('${mirror().path}.lock'),
    );
    try {
      final result = await resolver.pruneMirrors();
      expect(result.removed, isEmpty);
      expect(result.busy, contains(owned.path));
    } finally {
      await held.release();
    }
    final before = await fileSnapshot(data.path);
    final preview = await resolver.pruneMirrors(dryRun: true);
    expect(preview.candidates.single.path, owned.path);
    expect(await fileSnapshot(data.path), before);
    final result = await resolver.pruneMirrors();
    expect(result.removed.single.path, owned.path);
    expect(
      result.removed.single.reason,
      ProfileMirrorPruneReason.abandonedTemporary,
    );
    expect(await unowned.exists(), isTrue);
    expect(await recent.exists(), isTrue);
  });

  test('metadata and lock symlinks are never followed', () async {
    await resolver.resolve(project.path);
    final target = File(p.join(temp.path, 'keep'));
    await target.writeAsString('keep');
    await metadata(mirror()).delete();
    final metadataLink = Link(metadata(mirror()).path);
    await metadataLink.create(target.path);
    expect((await resolver.pruneMirrors()).errors, hasLength(1));
    await metadataLink.delete();
    final lock = File('${mirror().path}.lock');
    await lock.delete();
    await Link(lock.path).create(target.path);
    expect((await resolver.pruneMirrors()).errors, hasLength(1));
    expect(await target.readAsString(), 'keep');
    expect(await mirror().exists(), isTrue);
  });

  test('a symlinked cache root is not traversed', () async {
    final target = await Directory(p.join(temp.path, 'other-cache')).create();
    await Directory(p.join(target.path, 'c' * 64)).create();
    await data.create();
    await Link(p.join(data.path, 'profiles')).create(target.path);
    final before = await fileSnapshot(target.path);
    final result = await resolver.pruneMirrors();
    expect(result.errors, hasLength(1));
    expect(await fileSnapshot(target.path), before);
  });

  test('source lookup errors are not evidence of disappearance', () async {
    final parent = await Directory(p.join(temp.path, 'inaccessible')).create();
    final root = await legacy(p.join(parent.path, 'source'));
    await Process.run('chmod', ['000', parent.path]);
    try {
      try {
        await parent.list().toList();
        markTestSkipped(
          'This user can list directories without read permission.',
        );
        return;
      } on FileSystemException {
        // The lookup is actually denied for this user.
      }
      final result = await resolver.pruneMirrors();
      expect(result.removed, isEmpty);
      expect(result.errors, hasLength(1));
      expect(await root.exists(), isTrue);
    } finally {
      await Process.run('chmod', ['700', parent.path]);
    }
  }, skip: Platform.isWindows ? 'POSIX permission probe' : false);

  test('file URLs identify missing local sources', () async {
    final root = await legacy(
      Uri.file(p.join(temp.path, 'missing source')).toString(),
    );
    final result = await resolver.pruneMirrors();
    expect(result.removed.single.path, root.path);
    expect(
      result.removed.single.reason,
      ProfileMirrorPruneReason.missingSource,
    );
  });

  test('legacy origins preserve spaces in local source paths', () async {
    final root = await legacy(p.join(temp.path, 'gone source '));
    expect((await resolver.pruneMirrors()).removed.single.path, root.path);
  });

  test(
    'missing caches stay absent and negative retention is refused',
    () async {
      expect((await resolver.pruneMirrors(dryRun: true)).candidates, isEmpty);
      expect((await resolver.pruneMirrors()).removed, isEmpty);
      expect(await data.exists(), isFalse);
      await expectLater(
        resolver.pruneMirrors(unusedFor: const Duration(days: -1)),
        throwsArgumentError,
      );
    },
  );

  test('a plan still applies after its mirror is collected', () async {
    final plan = await resolver.plan(project.path);
    await source.delete(recursive: true);
    expect((await resolver.pruneMirrors()).removed, hasLength(1));
    final result = await resolver.apply(plan);
    expect(result.packages, isNotEmpty);
    expect(
      await resolver.select(p.join(project.path, 'knowledge')),
      isA<SelectedProfile>(),
    );
  });

  test(
    'a partial deletion retries without Git config or stale timestamps',
    () async {
      await resolver.resolve(project.path);
      final record = jsonDecode(await metadata(mirror()).readAsString()) as Map;
      record['deleting'] = 'unused';
      await metadata(mirror()).writeAsString(jsonEncode(record));
      await File(p.join(mirror().path, 'config')).delete();
      final withoutGit = WayfinderProfileResolver(
        dataDirectory: data,
        git: (arguments, {workingDirectory, cancel}) => fail('prune ran Git'),
      );
      expect(
        (await withoutGit.pruneMirrors()).removed.single.path,
        mirror().path,
      );
    },
  );

  test('partial deletion remains retryable on Windows', () async {
    await resolver.resolve(project.path);
    await age(mirror());
    final blocked = File(p.join(mirror().path, 'objects', 'held'));
    await blocked.writeAsString('held');
    final handle = await blocked.open();
    try {
      final result = await resolver.pruneMirrors();
      if (Platform.isWindows) {
        expect(result.errors, hasLength(1));
        expect(await metadata(mirror()).exists(), isTrue);
      } else {
        expect(result.removed, hasLength(1));
      }
    } finally {
      await handle.close();
    }
    if (Platform.isWindows) {
      // Git config may already have been deleted; retry uses the retained
      // deletion record rather than trying to rediscover a legacy mirror.
      expect(
        (await resolver.pruneMirrors()).removed.single.path,
        mirror().path,
      );
    }
    expect(await mirror().exists(), isFalse);
  });
}

Future<Map<String, DateTime>> _modifiedTimes(Directory root) async => {
  root.path: (await root.stat()).modified,
  await for (final entity in root.list(recursive: true, followLinks: false))
    entity.path: (await entity.stat()).modified,
};

Future<List<String>> _busyInOtherIsolate(String dataPath) =>
    Isolate.run(() async {
      final result = await WayfinderProfileResolver(
        dataDirectory: Directory(dataPath),
      ).pruneMirrors();
      return result.busy;
    });
