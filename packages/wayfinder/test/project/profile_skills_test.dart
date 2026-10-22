import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

const _claude = '.claude/skills/acme-notes';
const _agents = '.agents/skills/acme-notes';

void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late WayfinderProfileResolver resolver;

  Future<String> commit() => _gitOutput(source.path, ['rev-parse', 'HEAD']);

  Future<void> commitSource() async {
    await _git(source.path, ['add', '-A']);
    await _git(source.path, ['commit', '-q', '-m', 'Profile']);
  }

  File sourceFile(String path) =>
      File(p.joinAll([source.path, 'profile', ...p.posix.split(path)]));

  Future<void> writeSource(String path, String text) async {
    await sourceFile(path).parent.create(recursive: true);
    await sourceFile(path).writeAsString(text);
  }

  String marker(String commit) =>
      '{\n  "id": "acme-notes",\n  "release": "1.0",\n  "commit": "$commit"\n}\n';

  Future<Map<String, String>> installed(String directory) async {
    final root = Directory(p.join(project.path, directory));
    return {
      await for (final entry in root.list(recursive: true))
        if (entry is File)
          p.posix.joinAll(p.split(p.relative(entry.path, from: root.path))):
              await entry.readAsString(),
    };
  }

  Future<ProfileValidationResult> validate() => validateWithProfileSources(
    p.join(project.path, 'knowledge'),
    resolver: resolver,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-profile-skills-');
    source = await Directory(p.join(temp.path, 'source')).create();
    project = await Directory(p.join(temp.path, 'project')).create();
    resolver = WayfinderProfileResolver(
      dataDirectory: Directory(p.join(temp.path, 'data')),
    );
    await _git(source.path, ['init', '-q', '-b', 'main']);
    await _git(source.path, ['config', 'user.email', 'test@example.test']);
    await _git(source.path, ['config', 'user.name', 'Wayfinder Test']);
    await _copy(
      '../../examples/profiles/two-rule',
      p.join(source.path, 'profile'),
    );
    await commitSource();
    await _copy(
      '../../examples/acme-notes/knowledge',
      p.join(project.path, 'knowledge'),
    );
    await File(p.join(project.path, 'wayfinder.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'profiles': {
          'acme-notes': {
            'source': {'git': source.path, 'ref': 'main', 'path': 'profile'},
            'applies_to': ['./knowledge'],
          },
        },
      }),
    );
  });

  tearDown(() => temp.delete(recursive: true));

  test(
    'get installs the skill from the locked commit in both agent roots',
    () async {
      final result = await resolver.resolve(project.path);
      final expected = {
        'SKILL.md': await sourceFile('skill/SKILL.md').readAsString(),
        '.wayfinder-profile': marker(await commit()),
      };
      expect(await installed(_claude), expected);
      expect(await installed(_agents), expected);
      expect(result.toJson()['skills'], [
        {
          'id': 'acme-notes',
          'directories': [_claude, _agents],
          'written': true,
        },
      ]);
      expect(result.removedSkills, isEmpty);
      expect(result.reused, isFalse);
      final validation = await validate();
      expect(validation.gate, GateState.pass);
      expect(validation.diagnostics, isEmpty);
    },
  );

  test('a second get writes nothing', () async {
    await resolver.resolve(project.path);
    final before = await _stat(project.path);
    final again = await resolver.resolve(project.path);
    expect(await _stat(project.path), before);
    expect(again.reused, isTrue);
    expect(again.skills.single.written, isFalse);
  });

  test('a directory without the marker belongs to the user', () async {
    final mine = File(p.join(project.path, _agents, 'SKILL.md'));
    await mine.parent.create(recursive: true);
    await mine.writeAsString('mine');
    await expectLater(
      resolver.resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          '$_agents already exists without a .wayfinder-profile marker, so '
              'wayfinder did not install it. Move it aside and run the '
              'command again to install the Profile skill there.',
        ),
      ),
    );
    expect(await installed(_agents), {'SKILL.md': 'mine'});
    expect(await Directory(p.join(project.path, _claude)).exists(), isFalse);
    expect(
      await File(p.join(project.path, 'wayfinder.lock')).exists(),
      isFalse,
    );
  });

  test('upgrade replaces the skill with the new commit', () async {
    await writeSource('skill/references/old.md', 'old');
    await commitSource();
    await resolver.resolve(project.path);
    expect((await installed(_claude)).keys, contains('references/old.md'));

    await sourceFile('skill/references/old.md').delete();
    await writeSource('skill/SKILL.md', '---\nname: acme-notes\n---\nnew\n');
    await commitSource();
    final upgraded = await resolver.resolve(project.path, upgrade: true);
    final expected = {
      'SKILL.md': '---\nname: acme-notes\n---\nnew\n',
      '.wayfinder-profile': marker(await commit()),
    };
    expect(await installed(_claude), expected);
    expect(await installed(_agents), expected);
    expect(upgraded.skills.single.written, isTrue);
    final hidden = await Directory(
      p.join(project.path, '.claude/skills'),
    ).list().map((entry) => p.basename(entry.path)).toList();
    expect(hidden, ['acme-notes']);
  });

  test('a marked directory goes when its Profile stops shipping it', () async {
    Future<Directory> marked(String path, String id) async {
      final directory = await Directory(
        p.join(project.path, path),
      ).create(recursive: true);
      await File(p.join(directory.path, '.wayfinder-profile')).writeAsString(
        jsonEncode({'id': id, 'release': '1', 'commit': 'a' * 40}),
      );
      return directory;
    }

    final retired = await marked(
      '.claude/skills/retired-profile',
      'retired-profile',
    );
    final interrupted = await marked(
      '.agents/skills/.acme-notes.old-12-34',
      'acme-notes',
    );
    final mine = await Directory(
      p.join(project.path, '.claude/skills/mine'),
    ).create();
    final unmarkedStaging = await Directory(
      p.join(project.path, '.agents/skills/.acme-notes.staged-56-78'),
    ).create();
    final claimedByAnother = await marked(
      '.agents/skills/.acme-notes.staged-9-10',
      'other-profile',
    );
    final first = await resolver.resolve(project.path);
    expect(first.removedSkills, ['.claude/skills/retired-profile']);
    expect(await retired.exists(), isFalse);
    expect(await interrupted.exists(), isFalse);
    expect(await unmarkedStaging.exists(), isTrue);
    expect(await claimedByAnother.exists(), isTrue);

    final package = sourceFile('wayfinder-profile.json');
    await package.writeAsString(
      (await package.readAsString()).replaceFirst('  "skill": "skill",\n', ''),
    );
    await commitSource();
    final upgraded = await resolver.resolve(project.path, upgrade: true);
    expect(upgraded.skills, isEmpty);
    expect(upgraded.removedSkills, [_claude, _agents]);
    expect(await Directory(p.join(project.path, _claude)).exists(), isFalse);
    expect(await Directory(p.join(project.path, _agents)).exists(), isFalse);
    expect(await mine.exists(), isTrue);
    expect((await validate()).diagnostics, isEmpty);
  });

  test('a stale skill is a warning that leaves the gate alone', () async {
    await resolver.resolve(project.path);
    final locked = await commit();
    await File(
      p.join(project.path, _claude, '.wayfinder-profile'),
    ).writeAsString(marker('f' * 40));
    final stale = await validate();
    expect(stale.gate, GateState.pass);
    expect(stale.exitCode, 0);
    expect(stale.diagnostics.map((d) => d.toJson()), [
      {
        'id': 'wayfinder/profile-skill-stale',
        'level': 'warning',
        'message':
            'Profile acme-notes skill in $_claude is not the locked commit '
            '$locked. Run wayfinder get.',
        'location': {'path': 'wayfinder.json'},
      },
    ]);

    await Directory(p.join(project.path, _agents)).delete(recursive: true);
    expect(
      (await validate()).diagnostics.single.message,
      'Profile acme-notes skill in $_claude and $_agents is not the locked '
      'commit $locked. Run wayfinder get.',
    );

    final repaired = await resolver.resolve(project.path);
    expect(repaired.skills.single.written, isTrue);
    expect(repaired.reused, isFalse);
    expect((await validate()).diagnostics, isEmpty);
  });

  test('a marker that cannot be read marks no revision, so the skill is stale '
      'and the directory stays the user\'s', () async {
    await resolver.resolve(project.path);
    final locked = await commit();
    final unreadable = File(
      p.join(project.path, _claude, '.wayfinder-profile'),
    );
    await _run('chmod', ['000', unreadable.path]);
    addTearDown(() => _run('chmod', ['644', unreadable.path]));
    try {
      await unreadable.readAsString();
      markTestSkipped('this user reads a file whose mode is 000');
      return;
    } on FileSystemException {
      // Unreadable, as the test needs.
    }
    final stale = [
      {
        'id': 'wayfinder/profile-skill-stale',
        'level': 'warning',
        'message':
            'Profile acme-notes skill in $_claude is not the locked commit '
            '$locked. Run wayfinder get.',
        'location': {'path': 'wayfinder.json'},
      },
    ];

    final selection =
        await resolver.select(p.join(project.path, 'knowledge'))
            as SelectedProfile;
    expect(selection.notes.map((note) => note.toJson()), stale);
    final validation = await validate();
    expect(validation.gate, GateState.pass);
    expect(validation.diagnostics.map((d) => d.toJson()), stale);
    final status = (await resolver.status(
      project.path,
    )).of(ProfileId.parse('acme-notes'))!;
    expect(status.state, ProfileBindingState.resolved);
    expect(status.notes.map((note) => note.toJson()), stale);

    final skill = File(p.join(project.path, _claude, 'SKILL.md'));
    final before = (
      await skill.readAsString(),
      (await unreadable.stat()).modeString(),
      (await unreadable.stat()).modified,
    );
    await expectLater(
      resolver.resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          startsWith(
            '$_claude already exists without a .wayfinder-profile marker, '
            'so wayfinder did not install it.',
          ),
        ),
      ),
    );
    expect((
      await skill.readAsString(),
      (await unreadable.stat()).modeString(),
      (await unreadable.stat()).modified,
    ), before);
  }, skip: Platform.isWindows ? 'chmod is POSIX' : false);

  group('read', () {
    late SkillRevision revision;
    late String text;

    Future<String?> read() async =>
        (await ProfileSkills.read(project.path, revision))?.text;

    Future<void> mark(String directory, String commit) => File(
      p.join(project.path, directory, '.wayfinder-profile'),
    ).writeAsString(marker(commit));

    Future<void> writeSkill(String text) async {
      for (final directory in [_claude, _agents]) {
        await File(
          p.join(project.path, directory, 'SKILL.md'),
        ).writeAsString(text);
      }
    }

    setUp(() async {
      text = await sourceFile('skill/SKILL.md').readAsString();
      revision = (
        id: ProfileId.parse('acme-notes'),
        release: '1.0',
        commit: await commit(),
      );
    });

    test('returns the installed SKILL.md of the selected revision', () async {
      expect(await read(), isNull);
      await resolver.resolve(project.path);
      final selection = await resolver.select(
        p.join(project.path, 'knowledge'),
      );
      expect(ProfileSkills.revisionsOf(selection as SelectedProfile), [
        revision,
      ]);
      expect(await ProfileSkills.read(project.path, revision), (
        text: text,
        truncated: false,
      ));
      expect(
        ProfileSkills.revisionsOf(
          SelectedProfile(selection.profile, config: selection.config),
        ),
        isEmpty,
      );
    });

    test('a selection names the project root of the wayfinder.json that '
        'bound it', () async {
      await resolver.resolve(project.path);
      final bundle = p.join(project.path, 'knowledge');
      for (final selection in [
        await resolver.select(bundle),
        // A host's root above the project only bounds the search.
        await resolver.select(bundle, projectRoot: temp.path),
        await resolver.select(
          bundle,
          configPath: p.join(project.path, 'wayfinder.json'),
        ),
      ]) {
        selection as SelectedProfile;
        expect(selection.projectRoot, p.normalize(project.absolute.path));
        expect(p.dirname(selection.config!.file), selection.projectRoot);
        expect(
          await ProfileSkills.read(
            selection.projectRoot!,
            ProfileSkills.revisionsOf(selection).single,
          ),
          (text: text, truncated: false),
        );
      }
      final byHand = await resolver.select(bundle) as SelectedProfile;
      expect(
        SelectedProfile(byHand.profile, config: byHand.config).projectRoot,
        isNull,
      );
    });

    test('skips a directory the staleness check rejects', () async {
      await resolver.resolve(project.path);
      await File(
        p.join(project.path, _agents, 'SKILL.md'),
      ).writeAsString('agents copy');
      await mark(_claude, 'f' * 40);
      expect(await ProfileSkills.stale(project.path, revision), [_claude]);
      expect(await read(), 'agents copy');
      await mark(_agents, 'f' * 40);
      expect(await read(), isNull);
      await Directory(p.join(project.path, _claude)).delete(recursive: true);
      await Directory(p.join(project.path, _agents)).delete(recursive: true);
      expect(await read(), isNull);
    });

    test('skips a SKILL.md that is not UTF-8 text', () async {
      await resolver.resolve(project.path);
      await File(
        p.join(project.path, _claude, 'SKILL.md'),
      ).writeAsBytes([0x61, 0xff, 0x62]);
      await File(
        p.join(project.path, _agents, 'SKILL.md'),
      ).writeAsString('agents copy');
      expect(await read(), 'agents copy');
      expect(await ProfileSkills.read(project.path, revision, maxBytes: 2), (
        text: 'agents copy'.substring(0, 2),
        truncated: true,
      ));
    });

    test(
      'reads nothing a symbolic link places outside the project',
      () async {
        await resolver.resolve(project.path);
        final outside = await File(
          p.join(temp.path, 'outside.md'),
        ).writeAsString('outside');
        final claudeSkill = File(p.join(project.path, _claude, 'SKILL.md'));
        await claudeSkill.delete();
        await Link(claudeSkill.path).create(outside.path);
        expect(await read(), text, reason: 'the .agents copy still holds it');

        final agents = Directory(p.join(project.path, _agents));
        final elsewhere = await agents.rename(p.join(temp.path, 'elsewhere'));
        await Link(agents.path).create(elsewhere.path);
        expect(await ProfileSkills.stale(project.path, revision), isEmpty);
        expect(await read(), isNull);
      },
      skip: Platform.isWindows ? 'needs symbolic links' : false,
    );

    test(
      'reads the real path it checked, not a link retargeted after the check',
      () async {
        await resolver.resolve(project.path);
        await File(
          p.join(project.path, _agents, 'SKILL.md'),
        ).writeAsString('agents copy');
        // The .claude copy lives elsewhere in the project, behind a link.
        final claude = Directory(p.join(project.path, _claude));
        final vendored = await claude.rename(p.join(project.path, 'vendor'));
        await Link(claude.path).create(vendored.path);
        expect(await read(), text);
        // Outside the project, a copy that marks the same revision.
        final outside = await Directory(p.join(temp.path, 'outside')).create();
        await File(
          p.join(outside.path, '.wayfinder-profile'),
        ).writeAsString(marker(revision.commit));
        await File(p.join(outside.path, 'SKILL.md')).writeAsString('outside');

        final swap = _OnFirstPath(
          (path) => p.basename(path) == 'SKILL.md',
          () => Link(claude.path).updateSync(outside.path),
        );
        final result = await IOOverrides.runWithIOOverrides(
          () => ProfileSkills.read(project.path, revision),
          swap,
        );
        expect(swap.fired, isTrue);
        expect(result, (text: text, truncated: false));
        expect(
          await Link(claude.path).target(),
          outside.path,
          reason: 'the link moved between the check and the read',
        );
      },
      skip: Platform.isWindows ? 'needs symbolic links' : false,
    );

    test(
      'never returns a file a symbolic link replaced after the check',
      () async {
        await resolver.resolve(project.path);
        await File(
          p.join(project.path, _agents, 'SKILL.md'),
        ).writeAsString('agents copy');
        final outside = await File(
          p.join(temp.path, 'outside.md'),
        ).writeAsString('outside');
        final checked = p.join(
          await project.resolveSymbolicLinks(),
          _claude,
          'SKILL.md',
        );
        final swap = _OnFirstPath((path) => p.equals(path, checked), () {
          File(checked).deleteSync();
          Link(checked).createSync(outside.path);
        });
        final result = await IOOverrides.runWithIOOverrides(
          () => ProfileSkills.read(project.path, revision),
          swap,
        );
        expect(swap.fired, isTrue, reason: 'it reads the real path');
        expect(result, (text: 'agents copy', truncated: false));
      },
      skip: Platform.isWindows ? 'needs symbolic links' : false,
    );

    test('never returns a text whose marker a symbolic link replaced while it '
        'read', () async {
      await resolver.resolve(project.path);
      await File(
        p.join(project.path, _agents, 'SKILL.md'),
      ).writeAsString('agents copy');
      // Outside the project, a marker for the same revision.
      final outside = await File(
        p.join(temp.path, 'outside-marker'),
      ).writeAsString(marker(revision.commit));
      final real = await project.resolveSymbolicLinks();
      final checkedMarker = p.join(real, _claude, '.wayfinder-profile');
      final swap = _OnFirstPath(
        (path) => p.equals(path, p.join(real, _claude, 'SKILL.md')),
        () {
          File(checkedMarker).deleteSync();
          Link(checkedMarker).createSync(outside.path);
        },
      );
      final result = await IOOverrides.runWithIOOverrides(
        () => ProfileSkills.read(project.path, revision),
        swap,
      );
      expect(swap.fired, isTrue);
      expect(result, (text: 'agents copy', truncated: false));
    }, skip: Platform.isWindows ? 'needs symbolic links' : false);

    test(
      'checks that SKILL.md is a regular file just before opening it',
      () async {
        await resolver.resolve(project.path);
        await File(
          p.join(project.path, _agents, 'SKILL.md'),
        ).writeAsString('agents copy');
        final real = await project.resolveSymbolicLinks();
        final skill = p.join(real, _claude, 'SKILL.md');
        // After SKILL.md was confined, while the marker is read, a named
        // pipe takes its place; opening it would wait for a writer.
        final swap = _OnFirstPath(
          (path) => p.equals(path, p.join(real, _claude, '.wayfinder-profile')),
          () {
            File(skill).deleteSync();
            final made = Process.runSync('mkfifo', [skill]);
            if (made.exitCode != 0) throw StateError('${made.stderr}');
          },
        );
        final result = await IOOverrides.runWithIOOverrides(
          () => ProfileSkills.read(project.path, revision),
          swap,
        ).timeout(const Duration(seconds: 10));
        expect(swap.fired, isTrue);
        expect(result, (text: 'agents copy', truncated: false));
      },
      skip: Platform.isWindows ? 'mkfifo is POSIX' : false,
    );

    test('never returns the text of a revision get puts in place while it '
        'reads', () async {
      await resolver.resolve(project.path);
      await File(
        p.join(project.path, _agents, 'SKILL.md'),
      ).writeAsString('agents copy');
      final checked = p.join(
        await project.resolveSymbolicLinks(),
        _claude,
        'SKILL.md',
      );
      final racing = _OnFirstPath((path) => p.equals(path, checked), () {
        // What `get` leaves after renaming a new revision into place.
        File(
          p.join(project.path, _claude, '.wayfinder-profile'),
        ).writeAsStringSync(marker('f' * 40));
        File(checked).writeAsStringSync('new revision');
      });
      final result = await IOOverrides.runWithIOOverrides(
        () => ProfileSkills.read(project.path, revision),
        racing,
      );
      expect(racing.fired, isTrue);
      expect(result, (text: 'agents copy', truncated: false));
    });

    test('maxBytes cuts a longer file at a character boundary', () async {
      await resolver.resolve(project.path);
      // 'a' is one byte, 'é' two, '€' three and '😀' four.
      await writeSkill('aé€😀');
      Future<ProfileSkillText?> readUpTo(int maxBytes) =>
          ProfileSkills.read(project.path, revision, maxBytes: maxBytes);
      expect(await readUpTo(10), (text: 'aé€😀', truncated: false));
      expect(await readUpTo(11), (text: 'aé€😀', truncated: false));
      for (final (maxBytes, start) in [
        (9, 'aé€'),
        (7, 'aé€'),
        (6, 'aé€'),
        (5, 'aé'),
        (3, 'aé'),
        (2, 'a'),
        (1, 'a'),
        (0, ''),
      ]) {
        expect(await readUpTo(maxBytes), (
          text: start,
          truncated: true,
        ), reason: '$maxBytes');
      }
      await writeSkill('');
      expect(await readUpTo(0), (text: '', truncated: false));
      await expectLater(readUpTo(-1), throwsRangeError);
    });

    test('maxBytes bounds what is read of a huge file', () async {
      await resolver.resolve(project.path);
      final huge = 'a' * (4 << 20);
      await writeSkill(huge);
      final counted = _CountingReads((path) => p.basename(path) == 'SKILL.md');
      final bounded = await IOOverrides.runWithIOOverrides(
        () => ProfileSkills.read(project.path, revision, maxBytes: 1000),
        counted,
      );
      expect(bounded, (text: 'a' * 1000, truncated: true));
      expect(counted.bytes, lessThanOrEqualTo(1001));

      final unbounded = _CountingReads(
        (path) => p.basename(path) == 'SKILL.md',
      );
      final whole = await IOOverrides.runWithIOOverrides(
        () => ProfileSkills.read(project.path, revision),
        unbounded,
      );
      expect(whole, (text: huge, truncated: false));
      expect(unbounded.bytes, huge.length);
    });

    test('a marker larger than 64 KiB marks no revision', () async {
      await resolver.resolve(project.path);
      final padded = marker(
        revision.commit,
      ).replaceFirst('{', '{${' ' * (64 * 1024)}');
      await File(
        p.join(project.path, _claude, '.wayfinder-profile'),
      ).writeAsString(padded);
      expect(await ProfileSkills.stale(project.path, revision), [_claude]);
      await File(
        p.join(project.path, _agents, 'SKILL.md'),
      ).writeAsString('agents copy');
      expect(await read(), 'agents copy');
      await File(
        p.join(project.path, _agents, '.wayfinder-profile'),
      ).writeAsString(padded);
      expect(await read(), isNull);
      // Wayfinder's own markers are far smaller.
      expect(
        utf8.encode(ProfileSkills.markerText(revision)).length,
        lessThan(1024),
      );
    });

    test(
      'a marker that is not a regular file marks no revision',
      () async {
        await resolver.resolve(project.path);
        final fifo = p.join(project.path, _claude, '.wayfinder-profile');
        await File(fifo).delete();
        await _run('mkfifo', [fifo]);
        // Opening a FIFO with no writer would wait forever.
        expect(
          await ProfileSkills.stale(
            project.path,
            revision,
          ).timeout(const Duration(seconds: 10)),
          [_claude],
        );
        expect(await read().timeout(const Duration(seconds: 10)), text);
      },
      skip: Platform.isWindows ? 'mkfifo is POSIX' : false,
    );
  });

  test('a skill directory without SKILL.md fails get', () async {
    await sourceFile('skill/SKILL.md').delete();
    await writeSource('skill/notes.md', 'notes');
    await commitSource();
    await expectLater(
      resolver.resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          'Profile acme-notes skill profile/skill at ${source.path} '
              '(${await commit()}) has no SKILL.md.',
        ),
      ),
    );
    expect(
      await File(p.join(project.path, 'wayfinder.lock')).exists(),
      isFalse,
    );
  });

  test('a skill that ships an ownership marker fails get', () async {
    await writeSource(
      'skill/.wayfinder-profile',
      '{"id": "someone-else", "release": "1.0", "commit": "${'a' * 40}"}\n',
    );
    await commitSource();
    await expectLater(
      resolver.resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          'Profile acme-notes skill profile/skill at ${source.path} '
              '(${await commit()}) holds .wayfinder-profile, which is the '
              'marker wayfinder writes to own the installed directory.',
        ),
      ),
    );
    expect(await Directory(p.join(project.path, '.claude')).exists(), isFalse);
    expect(
      await File(p.join(project.path, 'wayfinder.lock')).exists(),
      isFalse,
    );

    await sourceFile('skill/.wayfinder-profile').delete();
    await writeSource('skill/notes/.wayfinder-profile', 'not the marker\n');
    await commitSource();
    await resolver.resolve(project.path);
    expect(await installed(_claude), {
      'SKILL.md': await sourceFile('skill/SKILL.md').readAsString(),
      'notes/.wayfinder-profile': 'not the marker\n',
      '.wayfinder-profile': marker(await commit()),
    });
  });

  test('SKILL.md must name the Profile id', () async {
    final cases = [
      ('---\nname: someone-else\n---\n', 'is named someone-else'),
      ('---\nname: "acme-notes-skill"\n---\n', 'is named acme-notes-skill'),
      ('---\ndescription: No name here\n---\n', 'has no name'),
      ('# acme-notes\n\nNo frontmatter.\n', 'has no name'),
    ];
    for (final (text, problem) in cases) {
      await writeSource('skill/SKILL.md', text);
      await commitSource();
      await expectLater(
        resolver.resolve(project.path),
        throwsA(
          isA<WayfinderProfileResolutionException>().having(
            (error) => error.message,
            'message',
            'Profile acme-notes skill profile/skill at ${source.path} '
                '(${await commit()}) SKILL.md $problem; agents key skills by '
                'that name, so it must be acme-notes.',
          ),
        ),
        reason: text,
      );
      expect(
        await Directory(p.join(project.path, '.claude')).exists(),
        isFalse,
        reason: text,
      );
    }
    await writeSource('skill/SKILL.md', '---\nname: "acme-notes"\n---\n');
    await commitSource();
    await resolver.resolve(project.path);
    expect(await installed(_claude), {
      'SKILL.md': '---\nname: "acme-notes"\n---\n',
      '.wayfinder-profile': marker(await commit()),
    });
  });

  test(
    'get keeps the executable bit a skill file has at the locked commit',
    () async {
      await writeSource('skill/scripts/check.sh', '#!/bin/sh\nexit 0\n');
      await _run('chmod', ['+x', sourceFile('skill/scripts/check.sh').path]);
      await commitSource();
      await resolver.resolve(project.path);
      for (final directory in [_claude, _agents]) {
        bool executable(String path) =>
            File(p.join(project.path, directory, path)).statSync().mode &
                0x40 !=
            0;
        expect(executable('scripts/check.sh'), isTrue, reason: directory);
        expect(executable('SKILL.md'), isFalse, reason: directory);
      }
    },
    skip: Platform.isWindows ? 'Windows has no executable bit' : false,
  );

  test('a skill that holds a symlink fails get', () async {
    await Link(
      p.join(source.path, 'profile', 'skill', 'outside'),
    ).create('../../../outside');
    await commitSource();
    await expectLater(
      resolver.resolve(project.path),
      throwsA(
        isA<WayfinderProfileResolutionException>().having(
          (error) => error.message,
          'message',
          'Profile acme-notes skill profile/skill at ${source.path} '
              '(${await commit()}) holds outside, which is not a regular file.',
        ),
      ),
    );
    expect(await Directory(p.join(project.path, '.claude')).exists(), isFalse);
  });

  test('a crafted tree entry outside the skill fails get and writes '
      'nothing', () async {
    for (final name in ['..', '.']) {
      Future<String> object(List<String> arguments, String input) =>
          _gitInput(source.path, arguments, input);
      final skill = await object(['hash-object', '-w', '--stdin'], 'skill\n');
      final outside = await object(['mktree'], '100644 blob $skill\tx\n');
      final skillTree = await object([
        'mktree',
      ], '100644 blob $skill\tSKILL.md\n040000 tree $outside\t$name\n');
      final package = await _gitOutput(source.path, [
        'rev-parse',
        'HEAD:profile/wayfinder-profile.json',
      ]);
      final profileTree = await object(
        ['mktree'],
        '100644 blob $package\twayfinder-profile.json\n'
        '040000 tree $skillTree\tskill\n',
      );
      final root = await object([
        'mktree',
      ], '040000 tree $profileTree\tprofile\n');
      final crafted = await _gitOutput(source.path, [
        'commit-tree',
        root,
        '-p',
        'HEAD',
        '-m',
        'crafted',
      ]);
      await _git(source.path, ['update-ref', 'refs/heads/main', crafted]);
      await expectLater(
        resolver.resolve(project.path, upgrade: true),
        throwsA(
          isA<WayfinderProfileResolutionException>().having(
            (error) => error.message,
            'message',
            'Profile acme-notes skill profile/skill at ${source.path} '
                '($crafted) holds "$name/x", which is not a path inside the '
                'skill.',
          ),
        ),
        reason: name,
      );
      expect(
        await Directory(p.join(project.path, '.claude')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(project.path, '.agents')).exists(),
        isFalse,
      );
      expect(await File(p.join(project.path, 'x')).exists(), isFalse);
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    }
  });

  test('write refuses a file path outside the skill before writing', () async {
    for (final path in ['../x', '/x', 'a/../../x']) {
      await expectLater(
        ProfileSkills.write(
          project.path,
          (id: ProfileId.parse('acme-notes'), release: '1.0', commit: 'a' * 40),
          [(path: path, bytes: utf8.encode('x'), executable: false)],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'is not a path inside the skill',
          ),
        ),
        reason: path,
      );
      expect(
        await Directory(p.join(project.path, '.claude')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(project.path, '.agents')).exists(),
        isFalse,
      );
    }
  });

  group(
    'a skill root behind a symbolic link inside the project',
    () {
      late Directory shared;
      late Directory other;
      late Directory foreign;
      final revision = (
        id: ProfileId.parse('acme-notes'),
        release: '1.0',
        commit: 'a' * 40,
      );
      final files = [
        (path: 'SKILL.md', bytes: utf8.encode('x'), executable: false),
      ];

      Future<Directory> marked(Directory directory, String id) async {
        await directory.create(recursive: true);
        await File(p.join(directory.path, '.wayfinder-profile')).writeAsString(
          jsonEncode({'id': id, 'release': '1', 'commit': 'b' * 40}),
        );
        return directory;
      }

      setUp(() async {
        shared = await Directory(
          p.join(project.path, 'shared', 'agents-skills'),
        ).create(recursive: true);
        await Directory(p.join(project.path, '.agents')).create();
        await Link(p.join(project.path, '.agents/skills')).create(shared.path);
        other = await Directory(p.join(temp.path, 'other')).create();
        foreign = await marked(
          Directory(p.join(other.path, '.agents/skills/old-profile')),
          'old-profile',
        );
      });

      // Points .agents/skills outside the project, as a concurrent change
      // could after the check.
      void retarget() => Link(
        p.join(project.path, '.agents/skills'),
      ).updateSync(p.join(other.path, '.agents/skills'));

      test('get installs and prunes there', () async {
        final retired = await marked(
          Directory(p.join(shared.path, 'retired-profile')),
          'retired-profile',
        );
        final result = await resolver.resolve(project.path);
        expect(result.removedSkills, ['.agents/skills/retired-profile']);
        expect(await installed(_agents), await installed(_claude));
        expect(
          await File(p.join(shared.path, 'acme-notes', 'SKILL.md')).exists(),
          isTrue,
        );
        expect(await retired.exists(), isFalse);
        expect(await foreign.exists(), isTrue);
      });

      test('write keeps to the real root it checked when the link moves '
          'afterwards', () async {
        final swap = _OnFirstPath(
          (path) => p.basename(path).startsWith('.acme-notes.staged-'),
          retarget,
          directories: true,
        );
        await IOOverrides.runWithIOOverrides(
          () => ProfileSkills.write(project.path, revision, files),
          swap,
        );
        expect(swap.fired, isTrue);
        expect(
          await File(
            p.join(shared.path, 'acme-notes', 'SKILL.md'),
          ).readAsString(),
          'x',
        );
        expect(
          await Directory(
            p.join(other.path, '.agents/skills'),
          ).list().map((entry) => p.basename(entry.path)).toList(),
          ['old-profile'],
        );
      });

      test('prune keeps to the real root it checked when the link moves '
          'afterwards', () async {
        final old = await marked(
          Directory(p.join(shared.path, 'old-profile')),
          'old-profile',
        );
        final swap = _OnFirstPath(
          (path) => p.basename(path) == '.wayfinder-profile',
          retarget,
        );
        final removed = await IOOverrides.runWithIOOverrides(
          () => ProfileSkills.prune(project.path, {}),
          swap,
        );
        expect(swap.fired, isTrue);
        expect(removed, ['.agents/skills/old-profile']);
        expect(await old.exists(), isFalse);
        expect(await foreign.exists(), isTrue);
      });
    },
    skip: Platform.isWindows ? 'needs symbolic links' : false,
  );

  test('write refuses to replace a directory without its marker', () async {
    final revision = (
      id: ProfileId.parse('acme-notes'),
      release: '1.0',
      commit: 'a' * 40,
    );
    final mine = await Directory(
      p.join(project.path, _agents),
    ).create(recursive: true);
    await File(p.join(mine.path, 'SKILL.md')).writeAsString('mine');
    await File(
      p.join(mine.path, '.wayfinder-profile'),
    ).writeAsString(marker('a' * 40).replaceFirst('acme-notes', 'other'));
    await expectLater(
      ProfileSkills.write(project.path, revision, [
        (path: 'SKILL.md', bytes: utf8.encode('x'), executable: false),
      ]),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          '$_agents exists without a .wayfinder-profile marker for '
              'acme-notes, so wayfinder did not replace it.',
        ),
      ),
    );
    expect(
      await Directory(
        p.join(project.path, '.agents/skills'),
      ).list().map((entry) => p.basename(entry.path)).toList(),
      ['acme-notes'],
      reason: 'nothing staged is left behind',
    );
    expect((await installed(_agents))['SKILL.md'], 'mine');
  });

  group('a skill root that resolves outside the project', () {
    late Directory other;
    late Directory foreign;

    setUp(() async {
      other = await Directory(p.join(temp.path, 'other')).create();
      foreign = Directory(p.join(other.path, '.agents/skills/old-profile'));
      await foreign.create(recursive: true);
      await File(p.join(foreign.path, '.wayfinder-profile')).writeAsString(
        '{"id": "old-profile", "release": "1", "commit": "${'b' * 40}"}',
      );
    });

    const message =
        '.agents/skills resolves outside the project through a symbolic '
        'link, so wayfinder did not install Profile skills there. Point it '
        'inside the project and run the command again.';

    for (final (name, link, target) in [
      ('at the root', '.agents/skills', '.agents/skills'),
      ('at an ancestor', '.agents', '.agents'),
    ]) {
      test('$name fails get before writing', () async {
        final path = p.join(project.path, link);
        await Directory(p.dirname(path)).create(recursive: true);
        await Link(path).create(p.join(other.path, target));
        await expectLater(
          resolver.resolve(project.path),
          throwsA(
            isA<WayfinderProfileResolutionException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
        expect(await foreign.exists(), isTrue);
        expect(await Directory(p.join(other.path, _agents)).exists(), isFalse);
        expect(
          await File(p.join(project.path, 'wayfinder.lock')).exists(),
          isFalse,
        );
      });
    }

    test('in both roots fails get naming each of them', () async {
      for (final link in ['.claude', '.agents']) {
        final target = await Directory(p.join(other.path, link)).create();
        await Link(p.join(project.path, link)).create(target.path);
      }
      await expectLater(
        resolver.resolve(project.path),
        throwsA(
          isA<WayfinderProfileResolutionException>().having(
            (error) => error.message,
            'message',
            '.claude/skills and .agents/skills resolve outside the project '
                'through a symbolic link, so wayfinder did not install '
                'Profile skills there. Point them inside the project and run '
                'the command again.',
          ),
        ),
      );
      expect(await foreign.exists(), isTrue);
      expect(await Directory(p.join(other.path, _claude)).exists(), isFalse);
      expect(await Directory(p.join(other.path, _agents)).exists(), isFalse);
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    });

    Future<void> linkRoot() async {
      await Directory(p.join(project.path, '.agents')).create();
      await Link(
        p.join(project.path, '.agents/skills'),
      ).create(p.join(other.path, '.agents/skills'));
    }

    test('write refuses it and prune leaves it alone', () async {
      await linkRoot();
      expect(await ProfileSkills.prune(project.path, {}), isEmpty);
      await expectLater(
        ProfileSkills.write(
          project.path,
          (id: ProfileId.parse('acme-notes'), release: '1.0', commit: 'a' * 40),
          [(path: 'SKILL.md', bytes: utf8.encode('x'), executable: false)],
        ),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            message,
          ),
        ),
      );
      expect(await foreign.exists(), isTrue);
      expect(await Directory(p.join(other.path, _agents)).exists(), isFalse);
    });

    test('get passes when no locked Profile ships a skill', () async {
      final package = sourceFile('wayfinder-profile.json');
      await package.writeAsString(
        (await package.readAsString()).replaceFirst(
          '  "skill": "skill",\n',
          '',
        ),
      );
      await commitSource();
      await linkRoot();
      final result = await resolver.resolve(project.path);
      expect(result.skills, isEmpty);
      expect(result.removedSkills, isEmpty);
      expect(await foreign.exists(), isTrue);
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isTrue,
      );
    });
  });
}

/// Runs [hook] once, outside the overrides, when the code under test first
/// names a file whose path [matches], or with [directories] a directory:
/// after any check of that path, just before using it.
final class _OnFirstPath extends IOOverrides {
  _OnFirstPath(this.matches, this.hook, {this.directories = false});

  final bool Function(String path) matches;
  final void Function() hook;
  final bool directories;
  var fired = false;

  void _named(String path) {
    if (fired || !matches(path)) return;
    fired = true;
    Zone.root.run(hook);
  }

  @override
  File createFile(String path) {
    _named(path);
    return super.createFile(path);
  }

  @override
  Directory createDirectory(String path) {
    if (directories) _named(path);
    return super.createDirectory(path);
  }

  // The inherited type lookup passes the native call a path without its
  // terminating NUL, so the real lookup runs outside the overrides instead.
  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) => Zone
      .root
      .run(() => FileSystemEntity.type(path, followLinks: followLinks));
}

/// Counts the bytes read from the files whose path [matches].
final class _CountingReads extends IOOverrides {
  _CountingReads(this.matches);

  final bool Function(String path) matches;
  var bytes = 0;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return matches(path) ? _CountingFile(file, this) : file;
  }

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) => Zone
      .root
      .run(() => FileSystemEntity.type(path, followLinks: followLinks));
}

final class _CountingFile implements File {
  _CountingFile(this._file, this._reads);

  final File _file;
  final _CountingReads _reads;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = await _file.readAsBytes();
    _reads.bytes += bytes.length;
    return bytes;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _CountingHandle(await _file.open(mode: mode), _reads);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CountingHandle implements RandomAccessFile {
  _CountingHandle(this._handle, this._reads);

  final RandomAccessFile _handle;
  final _CountingReads _reads;

  @override
  Future<Uint8List> read(int count) async {
    final bytes = await _handle.read(count);
    _reads.bytes += bytes.length;
    return bytes;
  }

  @override
  Future<void> close() => _handle.close();

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Map<String, (String?, DateTime)>> _stat(String root) async => {
  await for (final entity in Directory(root).list(recursive: true))
    p.relative(entity.path, from: root): (
      entity is File ? await entity.readAsString() : null,
      (await entity.stat()).modified,
    ),
};

Future<void> _copy(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

Future<String> _gitInput(
  String directory,
  List<String> arguments,
  String input,
) async {
  final process = await Process.start(
    'git',
    arguments,
    workingDirectory: directory,
  );
  process.stdin.write(input);
  await process.stdin.close();
  final output = await process.stdout.transform(utf8.decoder).join();
  if (await process.exitCode != 0) fail('git ${arguments.join(' ')} failed');
  return output.trim();
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Future<void> _git(String directory, List<String> arguments) async {
  await _gitOutput(directory, arguments);
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
