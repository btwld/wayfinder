import 'dart:io';

import 'package:path/path.dart' as p;

import '../wayfinder_config.dart';
import 'exception.dart';

/// A configured bundle: its folder [name], its project-relative [path], which
/// prefixes citations, and its canonical [root].
final class ProjectBundle {
  const ProjectBundle(this.name, this.path, this.root);

  final String name;
  final String path;
  final String root;

  Map<String, String> toJson() => {'name': name, 'path': path};
}

/// A project and the bundles it configures. Discovery reads existing
/// Profile application paths; it never fetches Profile sources.
final class WayfinderProject {
  const WayfinderProject._(this.root, this.config, this.bundles);

  /// The canonical directory holding `wayfinder.json`, or the conventional
  /// `knowledge/` directory when there is none.
  final String root;

  /// The project's `wayfinder.json`; null for a conventional project.
  final File? config;

  /// In path order, one per canonical root.
  final List<ProjectBundle> bundles;

  /// Finds the nearest `wayfinder.json` from [from] and its `applies_to`
  /// paths. Without one, the nearest `knowledge/` directory below the Git
  /// repository boundary is the project's one bundle. [bundleName] keeps
  /// only the bundle whose folder has that name.
  static Future<WayfinderProject> discover(
    Directory from, {
    String? bundleName,
  }) async {
    if (bundleName != null && bundleName.trim().isEmpty) {
      throw const WayfinderException(
        'bundle-name-invalid',
        '--bundle must be a nonblank bundle name.',
      );
    }
    var directory = Directory(await from.resolveSymbolicLinks());
    Directory? legacyProject;
    File? config;
    List<String>? paths;
    while (true) {
      final candidate = File(p.join(directory.path, 'wayfinder.json'));
      if (await candidate.exists()) {
        try {
          paths = WayfinderProjectConfig.parse(
            await candidate.readAsString(),
          ).bundles.map((bundle) => bundle.path).toList();
        } on WayfinderConfigException catch (error) {
          throw WayfinderException('config-invalid', error.message);
        } on FileSystemException catch (error) {
          throw WayfinderException(
            'config-invalid',
            'Cannot read ${candidate.path}: ${error.message}.',
          );
        }
        config = candidate;
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
          'bundles-missing',
          'No project bundles found. Configure wayfinder.json, create '
              'knowledge/, or pass an explicit bundle path.',
        );
      }
      directory = directory.parent;
    }
    paths.sort();
    final selected = paths
        .where((path) => bundleName == null || p.basename(path) == bundleName)
        .toList();
    if (selected.isEmpty) {
      throw WayfinderException(
        'bundle-unknown',
        'Unknown bundle "$bundleName". Available: '
            '${paths.map(p.basename).join(', ')}.',
      );
    }
    if (bundleName != null && selected.length > 1) {
      throw WayfinderException(
        'bundle-ambiguous',
        'Bundle name "$bundleName" is ambiguous: ${selected.join(', ')}. '
            'Pass an explicit bundle path.',
      );
    }
    final roots = <String>{};
    final bundles = <ProjectBundle>[];
    for (final path in selected) {
      final bundle = Directory(p.join(directory.path, path));
      if (!await bundle.exists()) {
        throw WayfinderException(
          'bundle-missing',
          'Configured bundle does not exist: $path.',
        );
      }
      final root = await bundle.resolveSymbolicLinks();
      if (!p.isWithin(directory.path, root)) {
        throw WayfinderException(
          'bundle-escapes',
          'Configured bundle leaves the project: $path.',
        );
      }
      if (roots.add(root)) {
        bundles.add(ProjectBundle(p.basename(path), path, root));
      }
    }
    return WayfinderProject._(
      directory.path,
      config,
      List.unmodifiable(bundles),
    );
  }
}

/// The citation prefix of an explicitly selected bundle [bundleRoot] when
/// launched from [workingDirectory]: its path relative to the enclosing
/// project, or to [workingDirectory], with a trailing `/`; empty when the
/// bundle is outside both.
Future<String> explicitBundlePrefix(
  Directory workingDirectory,
  String bundleRoot,
) async {
  final workingRoot = await workingDirectory.exists()
      ? await workingDirectory.resolveSymbolicLinks()
      : p.normalize(workingDirectory.absolute.path);
  final rawBundle = p.isAbsolute(bundleRoot)
      ? bundleRoot
      : p.join(workingRoot, bundleRoot);
  final bundleDir = Directory(rawBundle);
  final resolvedBundle = await bundleDir.exists()
      ? await bundleDir.resolveSymbolicLinks()
      : p.normalize(bundleDir.absolute.path);
  var directory = Directory(workingRoot);
  Directory? legacyProject;
  Directory? projectRoot;
  while (true) {
    if (await File(p.join(directory.path, 'wayfinder.json')).exists()) {
      projectRoot = directory;
      break;
    }
    if (await Directory(p.join(directory.path, 'knowledge')).exists()) {
      legacyProject ??= directory;
    }
    final hasGit =
        await FileSystemEntity.type(p.join(directory.path, '.git')) !=
        FileSystemEntityType.notFound;
    if (hasGit || directory.parent.path == directory.path) {
      projectRoot = legacyProject ?? (hasGit ? directory : null);
      break;
    }
    directory = directory.parent;
  }
  final base =
      projectRoot != null &&
          (p.equals(projectRoot.path, resolvedBundle) ||
              p.isWithin(projectRoot.path, resolvedBundle))
      ? projectRoot.path
      : workingRoot;
  return p.isWithin(base, resolvedBundle)
      ? '${p.posix.joinAll(p.split(p.relative(resolvedBundle, from: base)))}/'
      : '';
}
