// The tests read wayfinder.json and wayfinder.lock as decoded JSON.
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

final _bitwild = ProfileId.parse('bitwild-profile');

const _assistant = WayfinderActorMetadata(
  name: 'Claude Code over MCP',
  role: 'Authoring agent',
  side: 'tool',
);

/// [configuration] with the MCP actor registered, changing only its bytes.
String _addActor(String configuration) => (WayfinderConfigEditor.parse(
  configuration,
)..putActor(_bitwild, 'mcp:claude-code', _assistant)).encode(minimal: true);

void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late Directory data;
  late File config;
  late File lock;
  late List<List<String>> calls;
  late WayfinderProfileResolver resolver;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-relock-');
    (:source, :project, :data) = await bitwildProject(temp);
    config = File(p.join(project.path, 'wayfinder.json'));
    lock = File(p.join(project.path, 'wayfinder.lock'));
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
    await resolver.resolve(project.path);
    calls.clear();
  });

  tearDown(() => temp.delete(recursive: true));

  Future<ProfileLock> readLock() async =>
      ProfileLock.tryParse(jsonDecode(await lock.readAsString()))!;

  Future<Map<String, List<int>>> projectFiles() async => {
    for (final MapEntry(:key, :value) in (await fileSnapshot(
      project.path,
    )).entries)
      if (!key.startsWith('knowledge')) key: value,
  };

  test('relock registers an actor and locks it at exactly the locked '
      'commits, running no Git and writing no skill', () async {
    final before = await readLock();
    final configText = await config.readAsString();
    final claude = await fileSnapshot(p.join(project.path, '.claude'));
    // A skill directory that is gone stays gone: relock leaves skills alone.
    await Directory(
      p.join(project.path, '.agents', 'skills', 'bitwild-profile'),
    ).delete(recursive: true);
    // The source's tag moves on, which resolving the ref would follow.
    await File(p.join(source.path, 'NOTES.md')).writeAsString('Moved.\n');
    await fixtureGit(source.path, ['add', '.']);
    await fixtureGit(source.path, ['commit', '-q', '-m', 'Moved']);
    await fixtureGit(source.path, ['tag', '-f', 'v2026.3']);

    final result = await resolver.relock(
      project.path,
      edit: (text) {
        expect(text, configText);
        return _addActor(text);
      },
    );

    expect(calls, isEmpty, reason: 'relock runs no Git command');
    expect(result.configChanged, isTrue);
    expect(result.lockChanged, isTrue);
    final after = await readLock();
    expect(
      {
        for (final MapEntry(:key, :value) in after.packages.entries)
          key: value.toJson(),
      },
      {
        for (final MapEntry(:key, :value) in before.packages.entries)
          key: value.toJson(),
      },
    );
    expect(
      result.packages.values.map((package) => package.commit),
      before.packages.values.map((package) => package.commit),
    );
    final edited = await config.readAsString();
    expect(edited, _addActor(configText));
    expect(
      after.configurationSha256,
      WayfinderProfileResolver.canonicalConfigurationSha256(edited),
    );
    expect(
      WayfinderProjectConfig.parse(
        edited,
      ).profiles[_bitwild]!.project.actors.keys,
      contains('mcp:claude-code'),
    );

    final status = await resolver.status(project.path);
    expect(status.lockChange, isNull);
    expect(status.bindings.single.state, ProfileBindingState.resolved);
    expect(
      await resolver.select(p.join(project.path, 'knowledge')),
      isA<SelectedProfile>(),
    );
    expect(await fileSnapshot(p.join(project.path, '.claude')), claude);
    expect(
      Directory(
        p.join(project.path, '.agents', 'skills', 'bitwild-profile'),
      ).existsSync(),
      isFalse,
    );
    expect(calls, isEmpty);
  });

  test('relock keeps a lock that already matches, and locks a configuration '
      'an earlier edit made stale', () async {
    final unchanged = await projectFiles();
    final kept = await resolver.relock(project.path, edit: (text) => text);
    expect(kept.configChanged, isFalse);
    expect(kept.lockChanged, isFalse);
    expect(await projectFiles(), unchanged);

    // A person registers an actor by hand, which leaves the lock stale.
    await config.writeAsString(_addActor(await config.readAsString()));
    expect(
      (await resolver.status(project.path)).lockChange?.kind,
      ProfileLockChangeKind.configurationChanged,
    );
    final configBytes = await config.readAsBytes();
    final relocked = await resolver.relock(project.path, edit: (text) => text);
    expect(relocked.configChanged, isFalse);
    expect(relocked.lockChanged, isTrue);
    expect(await config.readAsBytes(), configBytes);
    expect((await resolver.status(project.path)).lockChange, isNull);
    expect(calls, isEmpty);
  });

  group('relock refuses before writing anything', () {
    Future<void> refuses(
      FutureOr<String> Function(String text) edit,
      Matcher matcher, {
      WayfinderCancellation? cancel,
    }) async {
      final before = await projectFiles();
      await expectLater(
        resolver.relock(project.path, edit: edit, cancel: cancel),
        throwsA(matcher),
      );
      expect(await projectFiles(), before);
      expect(calls, isEmpty);
    }

    String editSource(String text, String key, String value) {
      final json = jsonDecode(text) as Map<String, dynamic>;
      json['profiles']['bitwild-profile']['source'][key] = value;
      return jsonEncode(json);
    }

    Matcher lockChange(ProfileLockChangeKind kind, {ProfileId? profile}) =>
        isA<ProfileLockChangeRequiredException>()
            .having((error) => error.code, 'code', 'lock-change-required')
            .having((error) => error.change.kind, 'kind', kind)
            .having((error) => error.profile, 'profile', profile);

    test('an edit of a Profile source, ref or path', () async {
      await refuses(
        (text) => editSource(text, 'ref', 'main'),
        lockChange(ProfileLockChangeKind.sourceChanged, profile: _bitwild),
      );
      await refuses(
        (text) => editSource(text, 'path', 'profiles/other'),
        lockChange(ProfileLockChangeKind.sourceChanged, profile: _bitwild),
      );
      await refuses(
        (text) => editSource(text, 'git', p.join(temp.path, 'elsewhere')),
        lockChange(ProfileLockChangeKind.sourceChanged, profile: _bitwild),
      );
    });

    test('a new binding the lock holds no chain for', () async {
      await Directory(p.join(project.path, 'docs')).create();
      final client = ProfileId.parse('client-profile');
      await refuses((text) {
        final json = jsonDecode(text) as Map<String, dynamic>;
        json['profiles']['client-profile'] = {
          'source': {
            'git': source.path,
            'ref': 'v2026.3',
            'path': 'profiles/bitwild',
          },
          'applies_to': ['./docs'],
        };
        return jsonEncode(json);
      }, lockChange(ProfileLockChangeKind.chainMissing, profile: client));
    });

    test('a missing lock', () async {
      await lock.delete();
      await refuses(_addActor, lockChange(ProfileLockChangeKind.lockMissing));
      expect(lock.existsSync(), isFalse);
    });

    test('a lock that cannot be read, as the file system failure it is '
        'rather than a missing lock', () async {
      await lock.delete();
      // Reading a directory as a file fails as an unreadable lock does.
      await Directory(lock.path).create();
      await refuses(
        _addActor,
        isA<ProfileRelockFailedException>()
            .having((error) => error.code, 'code', 'relock-failed')
            .having((error) => error.partial, 'partial', isFalse)
            .having((error) => error.changed, 'changed', isEmpty)
            .having((error) => error.message, 'message', contains(lock.path)),
      );
      expect(Directory(lock.path).existsSync(), isTrue);
    });

    test('text that is not a valid configuration', () async {
      await refuses(
        (text) => '{"version": 1',
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'config-invalid',
        ),
      );
    });

    test('a configured bundle that does not exist', () async {
      await refuses(
        (text) => text.replaceFirst('./knowledge', './missing'),
        isA<WayfinderProfileResolutionException>(),
      );
    });

    test(
      'a locked package the Profile cache lacks, with what fills it',
      () async {
        await Directory(
          p.join(data.path, 'profiles', 'packages'),
        ).delete(recursive: true);
        await refuses(
          _addActor,
          isA<WayfinderProfileResolutionException>()
              .having((error) => error.code, 'code', 'profile-unresolved')
              .having(
                (error) => error.remedy,
                'remedy',
                DiagnosticRemedy.resolveProfilesFromMirror,
              ),
        );
      },
    );

    test('a cancellation, even one during the edit', () async {
      final cancel = WayfinderCancellationController();
      await refuses(
        (text) {
          cancel.cancel();
          return _addActor(text);
        },
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
        cancel: cancel,
      );
    });
  });

  test('relock refuses wayfinder.json that a writer holding no lock changed '
      'after it was read', () async {
    final lockBytes = await lock.readAsBytes();
    late String written;
    await expectLater(
      resolver.relock(
        project.path,
        edit: (text) async {
          written = '$text\n';
          await config.writeAsString(written);
          return _addActor(text);
        },
      ),
      throwsA(
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'resolution-stale',
        ),
      ),
    );
    expect(await config.readAsString(), written);
    expect(await lock.readAsBytes(), lockBytes);
  });

  test('a write that fails gives each file its original bytes back', () async {
    final before = await projectFiles();
    final overrides = _FailingLockWrite();
    await expectLater(
      IOOverrides.runWithIOOverrides(
        () => resolver.relock(project.path, edit: _addActor),
        overrides,
      ),
      throwsA(
        isA<ProfileRelockFailedException>()
            .having((error) => error.code, 'code', 'relock-failed')
            .having((error) => error.partial, 'partial', isFalse)
            .having((error) => error.changed, 'changed', isEmpty),
      ),
    );
    // wayfinder.json was written, then restored, around the failed lock.
    expect(overrides.configWrites, 2);
    expect(await projectFiles(), before);
  });

  test('a write whose restore fails too names the file it left changed, '
      'which status reports and relocking again repairs', () async {
    final lockBytes = await lock.readAsBytes();
    final edited = _addActor(await config.readAsString());
    final overrides = _FailingLockWrite(failRestore: true);
    await expectLater(
      IOOverrides.runWithIOOverrides(
        () => resolver.relock(project.path, edit: _addActor),
        overrides,
      ),
      throwsA(
        isA<ProfileRelockFailedException>()
            .having((error) => error.code, 'code', 'relock-failed')
            .having((error) => error.partial, 'partial', isTrue)
            .having((error) => error.changed.map(p.basename), 'changed', [
              'wayfinder.json',
            ]),
      ),
    );
    expect(overrides.configWrites, 2);
    expect(await config.readAsString(), edited);
    expect(await lock.readAsBytes(), lockBytes);
    expect(
      (await resolver.status(project.path)).lockChange?.kind,
      ProfileLockChangeKind.configurationChanged,
    );

    final repaired = await resolver.relock(project.path, edit: (text) => text);
    expect(repaired.configChanged, isFalse);
    expect(repaired.lockChanged, isTrue);
    expect((await resolver.status(project.path)).lockChange, isNull);
    expect(calls, isEmpty);
  });

  test('relock and get exclude each other', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final relocking = resolver.relock(
      project.path,
      edit: (text) async {
        entered.complete();
        await release.future;
        return _addActor(text);
      },
    );
    await entered.future;
    final plan = await resolver.plan(project.path);
    Matcher busy() => isA<ProfileResolutionBusyException>().having(
      (error) => error.code,
      'code',
      'resolution-busy',
    );
    await expectLater(resolver.resolve(project.path), throwsA(busy()));
    await expectLater(resolver.apply(plan), throwsA(busy()));
    await expectLater(
      resolver.relock(project.path, edit: (text) => text),
      throwsA(busy()),
    );
    release.complete();
    expect((await relocking).lockChanged, isTrue);
    // A plan made while the relock ran no longer applies.
    await expectLater(
      resolver.apply(plan),
      throwsA(
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'resolution-stale',
        ),
      ),
    );

    // A get that holds the project refuses a relock.
    final gitEntered = Completer<void>();
    final gitRelease = Completer<void>();
    final getting = WayfinderProfileResolver(
      dataDirectory: data,
      git: (arguments, {workingDirectory, cancel}) async {
        if (!gitEntered.isCompleted) {
          gitEntered.complete();
          await gitRelease.future;
        }
        return runGit(
          arguments,
          workingDirectory: workingDirectory,
          cancel: cancel,
        );
      },
    ).resolve(project.path);
    await gitEntered.future;
    final configBytes = await config.readAsBytes();
    await expectLater(
      resolver.relock(project.path, edit: _addActor),
      throwsA(busy()),
    );
    gitRelease.complete();
    await getting;
    expect(await config.readAsBytes(), configBytes);
  });
}

/// Fails the write of `wayfinder.lock`'s temporary file, after
/// `wayfinder.json` was written, and with [failRestore] each later write of
/// `wayfinder.json` too, such as the one that gives it its bytes back.
final class _FailingLockWrite extends IOOverrides {
  _FailingLockWrite({this.failRestore = false});

  final bool failRestore;

  /// How many temporary `wayfinder.json` files were created.
  var configWrites = 0;

  @override
  File createFile(String path) {
    final name = p.basename(path);
    final config = name.startsWith('wayfinder.json.tmp-');
    if (config) configWrites++;
    final fails =
        name.startsWith('wayfinder.lock.tmp-') ||
        (config && failRestore && configWrites > 1);
    return super.createFile(fails ? p.join(path, 'missing', 'file') : path);
  }

  // The inherited type lookup passes the native call a path without its
  // terminating NUL, so the real lookup runs outside the overrides instead.
  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) => Zone
      .root
      .run(() => FileSystemEntity.type(path, followLinks: followLinks));
}
