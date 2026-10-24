import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/adoption.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';

/// A project adopted through `package:wayfinder/adoption.dart` validates
/// with the `wayfinder` command. The library's own tests cover adoption in
/// depth.
void main() {
  late Directory temp;
  late Directory source;
  late Directory project;
  late Directory data;
  late List<String> output;
  late WayfinderCli cli;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-adopt-');
    source = await Directory(p.join(temp.path, 'source')).create();
    project = await Directory(p.join(temp.path, 'project')).create();
    data = Directory(p.join(temp.path, 'data'));
    for (final repository in [source, project]) {
      await _git(repository.path, ['init', '-q', '-b', 'main']);
      await _git(repository.path, [
        'config',
        'user.email',
        'test@example.test',
      ]);
      await _git(repository.path, ['config', 'user.name', 'Wayfinder Test']);
    }
    for (final package in ['profiles/bitwild', 'examples/profiles/two-rule']) {
      await _copy(
        p.joinAll(['..', '..', ...package.split('/')]),
        p.joinAll([source.path, ...package.split('/')]),
      );
    }
    await _git(source.path, ['add', '-A']);
    await _git(source.path, ['commit', '-q', '-m', 'Profiles']);
    output = [];
    cli = WayfinderCli(
      out: output.add,
      err: output.add,
      notices: false,
      profileResolver: () => WayfinderProfileResolver(dataDirectory: data),
    );
  });

  tearDown(() => temp.delete(recursive: true));

  Future<void> adopt(String profile, String path) async {
    final adoption = KnowledgeAdoption(
      resolver: WayfinderProfileResolver(dataDirectory: data),
    );
    final plan = await adoption.plan(
      AdoptionRequest(
        projectRoot: project.path,
        profile: ProfileId.parse(profile),
        source: AdoptionSource(git: source.path, path: path),
      ),
    );
    expect(plan.conflicts, isEmpty);
    expect((await adoption.apply(plan)).complete, isTrue);
  }

  for (final (profile, path) in [
    ('bitwild-profile', 'profiles/bitwild'),
    ('acme-notes', 'examples/profiles/two-rule'),
  ]) {
    test('validate reports PASS for a project adopted with $profile', () async {
      await adopt(profile, path);
      final code = await cli.run([
        'validate',
        p.join(project.path, 'knowledge'),
        '--output=json',
      ]);
      final report = jsonDecode(output.single) as Map<String, Object?>;
      expect(report['gate'], {'state': 'PASS'});
      expect((report['profile']! as Map)['id'], profile);
      expect(code, 0);
    });
  }
}

Future<void> _git(String directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

Future<void> _copy(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}
