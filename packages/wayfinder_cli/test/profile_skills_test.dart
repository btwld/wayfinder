import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/profile_resolver.dart';
import 'package:wayfinder_cli/src/profile_skills.dart';

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
          [(path: path, bytes: utf8.encode('x'))],
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
          [(path: 'SKILL.md', bytes: utf8.encode('x'))],
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

  test('get lists the installed skills', () async {
    final output = <String>[];
    final cli = WayfinderCli(
      out: output.add,
      err: (_) {},
      notices: false,
      profileResolver: () => resolver,
    );
    expect(await cli.run(['get', project.path]), 0);
    expect(output.last, 'Installed skill acme-notes → $_claude, $_agents');
    output.clear();
    expect(await cli.run(['get', project.path]), 0);
    expect(output.last, 'Current skill acme-notes → $_claude, $_agents');
  });
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
