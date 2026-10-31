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

  /// The canonical directory holding `wayfinder.json`, or, when there is
  /// none, the one holding the conventional `knowledge/` directory.
  final String root;

  /// The project's `wayfinder.json`; null for a conventional project.
  final File? config;

  /// In path order, one per canonical root.
  final List<ProjectBundle> bundles;

  /// Finds a project's bundles from [from].
  ///
  /// With [searchAncestors] false, the default, [from] is the project root,
  /// as a host knows the workspace or worktree it opens, and discovery reads
  /// nothing above it, not even to find a Git boundary: the bundles are the
  /// `applies_to` paths of its own `wayfinder.json`, or, without one, its
  /// `knowledge/` directory.
  ///
  /// With [searchAncestors] true, as the `wayfinder` command searches from
  /// its working directory, discovery finds the nearest `wayfinder.json` at
  /// or above [from] and its `applies_to` paths. Without one, the nearest
  /// `knowledge/` directory below the Git repository boundary is the
  /// project's one bundle.
  ///
  /// [bundleName] keeps only the bundle whose folder has that name. A
  /// [from] that does not exist or cannot be read is `bundles-missing`.
  static Future<WayfinderProject> discover(
    Directory from, {
    String? bundleName,
    bool searchAncestors = false,
  }) async {
    if (bundleName != null && bundleName.trim().isEmpty) {
      throw const WayfinderException(
        'bundle-name-invalid',
        '--bundle must be a nonblank bundle name.',
      );
    }
    final Directory start;
    try {
      start = Directory(await from.resolveSymbolicLinks());
    } on FileSystemException catch (error) {
      throw WayfinderException(
        'bundles-missing',
        'No project bundles found in ${from.path}: it does not exist or '
            'cannot be read (${error.osError?.message ?? error.message}).',
      );
    }
    final (directory, config, paths) = searchAncestors
        ? await _nearest(start)
        : await _atRoot(start);
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
      if (bundles.any(
        (other) =>
            p.equals(other.root, root) ||
            p.isWithin(other.root, root) ||
            p.isWithin(root, other.root),
      )) {
        throw const WayfinderException(
          'config-invalid',
          'Configured bundles overlap after resolving symlinks.',
        );
      }
      bundles.add(ProjectBundle(p.basename(path), path, root));
    }
    return WayfinderProject._(
      directory.path,
      config,
      List.unmodifiable(bundles),
    );
  }

  /// The bundles [root] itself configures, reading nothing above it.
  static Future<(Directory, File?, List<String>)> _atRoot(
    Directory root,
  ) async {
    final candidate = File(p.join(root.path, 'wayfinder.json'));
    if (await candidate.exists()) {
      return (root, candidate, await _configuredPaths(candidate));
    }
    if (await Directory(p.join(root.path, 'knowledge')).exists()) {
      return (root, null, ['knowledge']);
    }
    throw WayfinderException(
      'bundles-missing',
      'No project bundles found in ${root.path}: it holds neither '
          'wayfinder.json nor a knowledge/ directory.',
    );
  }

  /// The nearest configured project at or above [from], or the nearest
  /// `knowledge/` directory below the Git repository boundary.
  static Future<(Directory, File?, List<String>)> _nearest(
    Directory from,
  ) async {
    var directory = from;
    Directory? legacyProject;
    while (true) {
      final candidate = File(p.join(directory.path, 'wayfinder.json'));
      if (await candidate.exists()) {
        return (directory, candidate, await _configuredPaths(candidate));
      }
      if (await Directory(p.join(directory.path, 'knowledge')).exists()) {
        legacyProject ??= directory;
      }
      if (await FileSystemEntity.type(p.join(directory.path, '.git')) !=
              FileSystemEntityType.notFound ||
          directory.parent.path == directory.path) {
        if (legacyProject != null) return (legacyProject, null, ['knowledge']);
        throw const WayfinderException(
          'bundles-missing',
          'No project bundles found. Configure wayfinder.json, create '
              'knowledge/, or pass an explicit bundle path.',
        );
      }
      directory = directory.parent;
    }
  }

  static Future<List<String>> _configuredPaths(File config) async {
    try {
      return WayfinderProjectConfig.parse(
        await config.readAsString(),
      ).bundles.map((bundle) => bundle.path).toList();
    } on WayfinderConfigException catch (error) {
      throw WayfinderException('config-invalid', error.message);
    } on FileSystemException catch (error) {
      throw WayfinderException(
        'config-invalid',
        'Cannot read ${config.path}: ${error.message}.',
      );
    }
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
