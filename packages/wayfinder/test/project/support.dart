import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies the repository's Bitwild package into [repository] at
/// `profiles/bitwild`, as a Profile source repository holds it.
Future<void> copyBitwildPackage(String repository) async {
  final package = Directory(p.join('..', '..', 'profiles', 'bitwild'));
  await for (final entity in package.list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(
      p.join(
        repository,
        'profiles',
        'bitwild',
        p.relative(entity.path, from: package.path),
      ),
    );
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

/// Runs `git` in [directory] for a fixture and returns its trimmed stdout.
Future<String> fixtureGit(String directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}

/// A Git repository holding Bitwild at tag `v2026.3`, and a project whose
/// `knowledge/` bundle binds it, under [temp].
Future<({Directory source, Directory project, Directory data})> bitwildProject(
  Directory temp,
) async {
  final source = await Directory(p.join(temp.path, 'source')).create();
  final project = await Directory(p.join(temp.path, 'project')).create();
  await Directory(p.join(project.path, 'knowledge')).create();
  await fixtureGit(source.path, ['init', '-q']);
  await fixtureGit(source.path, ['config', 'user.email', 'test@example.test']);
  await fixtureGit(source.path, ['config', 'user.name', 'Wayfinder Test']);
  await copyBitwildPackage(source.path);
  await fixtureGit(source.path, ['add', '.']);
  await fixtureGit(source.path, ['commit', '-q', '-m', 'Profile']);
  await fixtureGit(source.path, ['tag', 'v2026.3']);
  await File(p.join(project.path, 'wayfinder.json')).writeAsString(
    jsonEncode({
      'version': 1,
      'profiles': {
        'bitwild-profile': {
          'source': {
            'git': source.path,
            'ref': 'v2026.3',
            'path': 'profiles/bitwild',
          },
          'applies_to': ['./knowledge'],
        },
      },
    }),
  );
  return (
    source: source,
    project: project,
    data: Directory(p.join(temp.path, 'data')),
  );
}

/// Every file under [root], by its relative path, with its bytes.
Future<Map<String, List<int>>> fileSnapshot(String root) async => {
  await for (final entity in Directory(root).list(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: root): await entity.readAsBytes(),
};
