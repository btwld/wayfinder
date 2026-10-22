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
      expect(errors.single, startsWith('wayfinder: Another wayfinder get'));
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
