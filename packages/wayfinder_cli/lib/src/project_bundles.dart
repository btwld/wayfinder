import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

import 'knowledge.dart';

/// A configured bundle, with a project-relative citation prefix.
class ProjectBundle {
  const ProjectBundle(this.name, this.path, this.root);

  final String name;
  final String path;
  final String root;

  Map<String, String> toJson() => {'name': name, 'path': path};
}

/// Reads existing Profile application paths; it never fetches Profile sources.
Future<List<ProjectBundle>> discoverProjectBundles(
  Directory from, {
  String? name,
}) async {
  if (name != null && name.trim().isEmpty) {
    throw const WayfinderException('--bundle must be a nonblank bundle name.');
  }
  var directory = Directory(await from.resolveSymbolicLinks());
  Directory? legacyProject;
  List<String>? paths;
  while (true) {
    final config = File(p.join(directory.path, 'wayfinder.json'));
    if (await config.exists()) {
      try {
        paths = (await WayfinderProjectConfig.read(
          config,
        )).bundles.map((bundle) => bundle.path).toList();
      } on WayfinderConfigException catch (error) {
        throw WayfinderException(error.message);
      }
      break;
    }
    if (await Directory(p.join(directory.path, 'knowledge')).exists()) {
      legacyProject ??= directory;
    }
    if (await FileSystemEntity.type(p.join(directory.path, '.git')) !=
            FileSystemEntityType.notFound ||
        directory.parent.path == directory.path) {
      if (legacyProject != null) {
        directory = legacyProject;
        paths = ['knowledge'];
        break;
      }
      throw const WayfinderException(
        'No project bundles found. Configure wayfinder.json, create knowledge/, '
        'or pass an explicit bundle path.',
      );
    }
    directory = directory.parent;
  }
  paths.sort();
  final selected = paths
      .where((path) => name == null || p.basename(path) == name)
      .toList();
  if (selected.isEmpty) {
    throw WayfinderException(
      'Unknown bundle "$name". Available: ${paths.map(p.basename).join(', ')}.',
    );
  }
  if (name != null && selected.length > 1) {
    throw WayfinderException(
      'Bundle name "$name" is ambiguous: ${selected.join(', ')}. '
      'Pass an explicit bundle path.',
    );
  }
  final roots = <String>{};
  final bundles = <ProjectBundle>[];
  for (final path in selected) {
    final bundle = Directory(p.join(directory.path, path));
    if (!await bundle.exists()) {
      throw WayfinderException('Configured bundle does not exist: $path.');
    }
    final root = await bundle.resolveSymbolicLinks();
    if (!p.isWithin(directory.path, root)) {
      throw WayfinderException('Configured bundle leaves the project: $path.');
    }
    if (roots.add(root)) {
      bundles.add(ProjectBundle(p.basename(path), path, root));
    }
  }
  return bundles;
}
