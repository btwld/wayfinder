import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';

import '../project/support.dart';

/// A copy of `examples/bitwild` under [temp], bound to a local Git source
/// that holds this checkout's Bitwild package, resolved, and committed to
/// its own Git repository so a test can check what a write changed.
Future<({String project, String bundle, WayfinderProfileResolver resolver})>
bitwildExample(Directory temp) async {
  final source = await Directory(p.join(temp.path, 'source')).create();
  await fixtureGit(source.path, ['init', '-q']);
  await _identify(source.path);
  await copyBitwildPackage(source.path);
  await fixtureGit(source.path, ['add', '.']);
  await fixtureGit(source.path, ['commit', '-q', '-m', 'Profile']);
  final commit = await fixtureGit(source.path, ['rev-parse', 'HEAD']);

  final project = p.join(temp.path, 'project');
  await copyDirectory(p.join('..', '..', 'examples', 'bitwild'), project);
  final configFile = File(p.join(project, 'wayfinder.json'));
  final config = jsonDecode(await configFile.readAsString()) as Map;
  for (final entry in (config['profiles'] as Map).values) {
    final binding = (entry as Map)['source'] as Map;
    binding['git'] = source.path;
    binding['ref'] = commit;
  }
  await configFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );
  final resolver = WayfinderProfileResolver(
    dataDirectory: Directory(p.join(temp.path, 'data')),
  );
  await resolver.resolve(project);

  await fixtureGit(project, ['init', '-q']);
  await _identify(project);
  await commitAll(project, 'Example');
  return (
    project: project,
    bundle: p.join(project, 'knowledge'),
    resolver: resolver,
  );
}

Future<void> copyDirectory(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

Future<void> commitAll(String repository, String message) async {
  await fixtureGit(repository, ['add', '-A']);
  await fixtureGit(repository, ['commit', '-q', '-m', message]);
}

Future<void> _identify(String repository) async {
  await fixtureGit(repository, ['config', 'user.email', 'test@example.test']);
  await fixtureGit(repository, ['config', 'user.name', 'Wayfinder Test']);
}
