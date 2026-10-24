import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_cli/src/cli.dart';

const _claude = '.claude/skills/acme-notes';
const _agents = '.agents/skills/acme-notes';

/// The `get` and `upgrade` commands over the core resolver, which
/// `package:wayfinder`'s own tests cover in depth.
void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late Directory data;
  late List<String> output;
  late List<String> errors;
  late WayfinderCli cli;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-get-');
    source = await Directory(p.join(temp.path, 'source')).create();
    project = await Directory(p.join(temp.path, 'project')).create();
    data = Directory(p.join(temp.path, 'data'));
    await _git(source.path, ['init', '-q', '-b', 'main']);
    await _git(source.path, ['config', 'user.email', 'test@example.test']);
    await _git(source.path, ['config', 'user.name', 'Wayfinder Test']);
    await _copy(
      '../../examples/profiles/two-rule',
      p.join(source.path, 'profile'),
    );
    await _git(source.path, ['add', '-A']);
    await _git(source.path, ['commit', '-q', '-m', 'Profile']);
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
    output = [];
    errors = [];
    cli = WayfinderCli(
      out: output.add,
      err: errors.add,
      notices: false,
      profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
    );
  });

  tearDown(() => temp.delete(recursive: true));

  test('get lists the installed skills', () async {
    expect(await cli.run(['get', project.path]), 0);
    expect(output.last, 'Installed skill acme-notes → $_claude, $_agents');
    output.clear();
    expect(await cli.run(['get', project.path]), 0);
    expect(output.first, startsWith('Profile sources already current for '));
    expect(output.last, 'Current skill acme-notes → $_claude, $_agents');
    expect(errors, isEmpty);
  });

  test('get and upgrade print the resolution as JSON', () async {
    expect(await cli.run(['get', project.path, '--output=json']), 0);
    expect(
      (jsonDecode(output.single) as Map)['packages'],
      contains('acme-notes'),
    );
    output.clear();
    expect(await cli.run(['upgrade', project.path, '--output=json']), 0);
    expect(jsonDecode(output.single), containsPair('upgraded', true));
    expect(errors, isEmpty);
  });

  test('validate keeps its verdict on a cache an earlier Wayfinder wrote, '
      'without fetching', () async {
    expect(await cli.run(['get', project.path]), 0);
    final knowledge = p.join(project.path, 'knowledge');
    final verdict = await cli.run(['validate', knowledge, '--output=json']);
    final report = output.last;
    expect(
      ((jsonDecode(report) as Map)['profile'] as Map)['state'],
      isNot('NOT ASSESSED'),
    );
    await Directory(
      p.join(data.path, 'profiles', 'packages'),
    ).delete(recursive: true);
    // A source the mirror cannot reach proves validation fetches nothing.
    await source.rename('${source.path}-moved');
    output.clear();
    expect(await cli.run(['validate', knowledge, '--output=json']), verdict);
    expect(output.last, report);
    expect(errors, isEmpty);
  });

  test('a get another process holds fails and names it', () async {
    final root = await project.resolveSymbolicLinks();
    final busy = (await WayfinderFileLock.tryExclusive(
      File(
        p.join(
          data.path,
          'projects',
          '${sha256.convert(utf8.encode(root))}.get.lock',
        ),
      ),
    ))!;
    try {
      expect(await cli.run(['get', project.path]), 2);
      expect(
        errors.single,
        'wayfinder: Another wayfinder get is changing ${project.path}. Retry '
        'when it finishes.',
      );
    } finally {
      await busy.release();
    }
    expect(
      await File(p.join(project.path, 'wayfinder.lock')).exists(),
      isFalse,
    );
    errors.clear();
    expect(await cli.run(['get', project.path]), 0);
    expect(errors, isEmpty);
  });

  group('the command says what to run where the libraries do not', () {
    late String commit;
    late String knowledge;

    setUp(() async {
      expect(await cli.run(['get', project.path]), 0);
      commit = await _gitOutput(source.path, ['rev-parse', 'HEAD']);
      knowledge = p.join(project.path, 'knowledge');
      output.clear();
    });

    Future<List<Object?>> diagnostics() async {
      output.clear();
      await cli.run(['validate', knowledge, '--output=json']);
      return (jsonDecode(output.single) as Map)['diagnostics'] as List;
    }

    Future<List<String>> diagnosticText() async {
      output.clear();
      await cli.run(['validate', knowledge]);
      return output;
    }

    test('in validation diagnostics', () async {
      await File(
        p.join(project.path, _claude, '.wayfinder-profile'),
      ).writeAsString(
        jsonEncode({'id': 'acme-notes', 'release': '1.0', 'commit': 'f' * 40}),
      );
      final stale =
          'Profile acme-notes skill in $_claude is not the locked commit '
          '$commit. Run wayfinder get.';
      expect(await diagnostics(), [
        {
          'id': 'wayfinder/profile-skill-stale',
          'level': 'warning',
          'message': stale,
          'location': {'path': 'wayfinder.json'},
        },
      ]);
      expect(
        await diagnosticText(),
        contains(
          'wayfinder.json: warning wayfinder/profile-skill-stale: '
          '$stale',
        ),
      );

      await File(p.join(project.path, 'wayfinder.lock')).delete();
      expect(
        ((await diagnostics()).single as Map)['message'],
        'Profile lock is missing or unreadable. Run wayfinder get.',
      );
      expect(await cli.run(['get', project.path]), 0);

      // A cache whose mirror another process holds keeps the package file
      // it lacks, so validation cannot restore it.
      await Directory(
        p.join(data.path, 'profiles', 'packages'),
      ).delete(recursive: true);
      final mirror = (await WayfinderFileLock.tryExclusive(
        File(
          p.join(
            data.path,
            'profiles',
            '${sha256.convert(utf8.encode(source.path))}.lock',
          ),
        ),
      ))!;
      try {
        expect(
          ((await diagnostics()).single as Map)['message'],
          'Profile acme-notes at ${source.path} ($commit) has no package '
          'file in the local cache, as in a cache an earlier Wayfinder wrote. '
          'Run wayfinder get; it fetches nothing while the cached source holds '
          'that commit.',
        );
      } finally {
        await mirror.release();
      }

      await data.delete(recursive: true);
      expect(
        ((await diagnostics()).single as Map)['message'],
        'Profile acme-notes at ${source.path} ($commit) is not in the local '
        'cache. Run wayfinder get.',
      );
      expect(errors, isEmpty);
    });

    test('when get may not replace a skill directory', () async {
      await Directory(p.join(project.path, _agents)).delete(recursive: true);
      await Directory(p.join(project.path, _agents)).create(recursive: true);
      expect(await cli.run(['get', project.path]), 2);
      expect(
        errors.single,
        'wayfinder: $_agents already exists without a .wayfinder-profile '
        'marker, so wayfinder did not install it. Move it aside and run the '
        'command again to install the Profile skill there.',
      );
      errors.clear();
      await Directory(p.join(project.path, '.agents')).delete(recursive: true);
      final elsewhere = await Directory(
        p.join(temp.path, 'elsewhere'),
      ).create();
      await Link(p.join(project.path, '.agents')).create(elsewhere.path);
      expect(await cli.run(['get', project.path]), 2);
      expect(
        errors.single,
        'wayfinder: .agents/skills resolves outside the project through a '
        'symbolic link, so wayfinder did not install Profile skills there. '
        'Point it inside the project and run the command again.',
      );
    });

    test('when the locked commit is gone from its source', () async {
      // Rewrite the source's only commit, and drop the old one, so neither
      // a fresh clone nor a refresh can find the locked commit.
      await _git(source.path, ['commit', '-q', '--amend', '-m', 'Rewritten']);
      await _git(source.path, ['reflog', 'expire', '--expire=now', '--all']);
      await _git(source.path, ['gc', '-q', '--prune=now']);
      await data.delete(recursive: true);
      expect(await cli.run(['get', project.path]), 2);
      expect(
        errors.single,
        'wayfinder: Locked commit $commit of ${source.path} is unavailable '
        'even after refreshing the source. Run wayfinder upgrade to select a '
        'new revision.',
      );
    });
  });
}

Future<void> _copy(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
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
