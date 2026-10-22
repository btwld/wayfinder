import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../project/support.dart';

export '../project/support.dart' show fileSnapshot, fixtureGit;

/// The Profile packages a test source repository holds, by their path in
/// this repository, which is also their path in the source.
const sourcePackages = ['profiles/bitwild', 'examples/profiles/two-rule'];

/// A local Git repository under [temp] holding this repository's Bitwild
/// and two-rule packages at their paths here, committed once on `main`, so
/// a `git:` source reaches them without the network.
Future<({Directory directory, String commit})> profileSource(
  Directory temp,
) async {
  final directory = await Directory(p.join(temp.path, 'source')).create();
  await fixtureGit(directory.path, ['init', '-q', '-b', 'main']);
  await _identify(directory.path);
  for (final package in sourcePackages) {
    await copyTree(p.joinAll(['..', '..', ...package.split('/')]), [
      directory.path,
      ...package.split('/'),
    ]);
  }
  await fixtureGit(directory.path, ['add', '.']);
  await fixtureGit(directory.path, ['commit', '-q', '-m', 'Profiles']);
  return (
    directory: directory,
    commit: await fixtureGit(directory.path, ['rev-parse', 'HEAD']),
  );
}

/// A second local Git repository under [temp] holding `client-profile` at
/// `profile`, whose package extends Bitwild from the repository [parent]
/// at `main`, committed once on `main`.
Future<Directory> clientSource(
  Directory temp, {
  required Directory parent,
}) async {
  final directory = await Directory(p.join(temp.path, 'client')).create();
  await fixtureGit(directory.path, ['init', '-q', '-b', 'main']);
  await _identify(directory.path);
  final package = File(
    p.join(directory.path, 'profile', 'wayfinder-profile.json'),
  );
  await package.parent.create(recursive: true);
  await package.writeAsString(
    jsonEncode({
      'format': 2,
      'id': 'client-profile',
      'release': '1',
      'implements': {'id': 'okf', 'release': '0.2'},
      'extends': {
        'git': parent.path,
        'ref': 'main',
        'path': 'profiles/bitwild',
      },
      'rules': <Object?>[],
    }),
  );
  await fixtureGit(directory.path, ['add', '.']);
  await fixtureGit(directory.path, ['commit', '-q', '-m', 'Client Profile']);
  return directory;
}

/// An empty Git repository under [temp], as a project before adoption.
Future<Directory> emptyRepository(Directory temp) async {
  final directory = await Directory(p.join(temp.path, 'project')).create();
  await fixtureGit(directory.path, ['init', '-q', '-b', 'main']);
  await _identify(directory.path);
  return directory;
}

/// Commits everything in [repository], so `git status` starts clean.
Future<void> commitAll(String repository) async {
  await fixtureGit(repository, ['add', '-A']);
  await fixtureGit(repository, ['commit', '-q', '-m', 'Fixture']);
}

/// `git status --porcelain` with every untracked file listed.
Future<List<String>> gitStatus(String repository) async {
  final text = await fixtureGit(repository, [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  return text.isEmpty ? const [] : text.split('\n');
}

/// Copies every file under [from] to the directory named by [to]'s
/// segments.
Future<void> copyTree(String from, List<String> to) async {
  final source = Directory(from);
  await for (final entity in source.list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(
      p.joinAll([...to, ...p.split(p.relative(entity.path, from: from))]),
    );
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

Future<void> _identify(String repository) async {
  await fixtureGit(repository, ['config', 'user.email', 'test@example.test']);
  await fixtureGit(repository, ['config', 'user.name', 'Wayfinder Test']);
  await fixtureGit(repository, ['config', 'commit.gpgsign', 'false']);
}
