import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

/// Non-filesystem root marking a bundle built entirely from retained bytes.
/// Validators require explicit outside-path observations for this input.
const String retainedBundleRoot = 'wayfinder:retained-bundle';

/// A path-valued target classified against the loaded bundle and, for a
/// relative path outside it, the optional bundle root on disk.
sealed class PathTarget {
  const PathTarget();

  /// Whether the target is a path that cannot be resolved.
  bool get missing;
}

/// A URL, prose, or other value the graph does not treat as a path.
final class NotAPath extends PathTarget {
  const NotAPath();

  @override
  bool get missing => false;
}

/// A path that is absent, malformed, or an absolute escape from the bundle.
final class MissingPath extends PathTarget {
  const MissingPath();

  @override
  bool get missing => true;
}

/// A file or implied directory in the loaded inventory.
final class InBundlePath extends PathTarget {
  const InBundlePath(this.path);

  /// Decoded bundle-relative path.
  final String path;

  @override
  bool get missing => false;
}

/// A relative path that leaves the bundle.
///
/// [missing] is false when no root was supplied, because that caller did not
/// ask for a disk check, and when the disk entry exists.
final class OutsidePath extends PathTarget {
  const OutsidePath({required this.missing, required this.relative});

  @override
  final bool missing;

  /// Decoded path relative to the bundle root, including a `../` prefix.
  final String relative;
}

/// Checks a path-valued field using the loaded inventory inside the bundle,
/// and optional disk lookup only for relative paths outside it.
///
/// URLs and prose descriptors are not missing paths. Explicit `/`, `./` and
/// `../` prefixes remain paths even when the graph classified whitespace as
/// prose. Percent decoding follows OKF; malformed escapes, separators within
/// decoded segments and bundle-root parent escapes are missing. A present
/// internal target returns its decoded bundle-relative path for display.
/// [outsideBundleExists], when supplied, replaces disk lookup for decoded
/// bundle-relative paths leaving the bundle. It is never called for internal
/// or invalid paths. Hosts must supply coherent observations; callback errors
/// propagate rather than becoming a successful check.
PathTarget resolvePathTarget(
  OkfGraphEdge edge, {
  required bool Function(String path) inBundle,
  String? rootPath,
  bool Function(String relative)? outsideBundleExists,
}) {
  const notPath = NotAPath();
  const missing = MissingPath();
  final raw = edge.rawTarget;
  if (raw.isEmpty || edge.resolution == OkfGraphResolution.external) {
    return notPath;
  }
  if (edge.resolution == OkfGraphResolution.descriptor &&
      !raw.startsWith('/') &&
      !raw.startsWith('./') &&
      !raw.startsWith('../')) {
    return notPath;
  }
  final cut = raw.indexOf(RegExp(r'[?#]'));
  final target = cut < 0 ? raw : raw.substring(0, cut);
  if (target.isEmpty) {
    return inBundle(edge.source.documentPath)
        ? InBundlePath(edge.source.documentPath)
        : missing;
  }
  final decoded = <String>[];
  for (final segment in target.split('/')) {
    final String value;
    try {
      value = segment.contains('%') ? Uri.decodeComponent(segment) : segment;
    } on ArgumentError {
      return missing;
    } on FormatException {
      return missing;
    }
    if (value.contains('/') ||
        value.contains(r'\') ||
        value.runes.any((rune) => rune < 32 || rune == 127)) {
      return missing;
    }
    decoded.add(value);
  }
  final directory = target.startsWith('/')
      ? '.'
      : p.posix.dirname(edge.source.documentPath);
  final relative = p.posix.normalize(p.posix.joinAll([directory, ...decoded]));
  final outside = relative == '..' || relative.startsWith('../');
  if (!outside) {
    return inBundle(relative) ? InBundlePath(relative) : missing;
  }
  if (target.startsWith('/')) return missing;
  if (outsideBundleExists != null) {
    return OutsidePath(
      missing: !outsideBundleExists(relative),
      relative: relative,
    );
  }
  if (rootPath == retainedBundleRoot) {
    throw StateError(
      'Retained bundle external paths require outsideBundleExists; live disk lookup is forbidden.',
    );
  }
  // An in-memory caller cannot inspect a relative path outside its inventory.
  if (rootPath == null) {
    return OutsidePath(missing: false, relative: relative);
  }
  try {
    return OutsidePath(
      missing:
          FileSystemEntity.typeSync(
            p.normalize(p.joinAll([rootPath, ...relative.split('/')])),
          ) ==
          FileSystemEntityType.notFound,
      relative: relative,
    );
  } on FileSystemException {
    return missing;
  }
}

/// Display path for a non-body citation of [target].
///
/// In-bundle targets use their decoded inventory path. Other present `./` and
/// `../` targets keep the historical undecoded prefix, so a citation label
/// does not change just because the path was classified. Missing targets stay
/// unlabeled.
String? pathTargetDisplay(PathTarget target, OkfGraphEdge edge) {
  switch (target) {
    case InBundlePath(:final path):
      return path;
    case MissingPath():
      return null;
    case NotAPath():
    case OutsidePath():
      if (target.missing) return null;
      return _historicalRelativeDisplay(edge);
  }
}

String? _historicalRelativeDisplay(OkfGraphEdge edge) {
  final raw = edge.rawTarget;
  if (!raw.startsWith('../') && !raw.startsWith('./')) return null;
  final cut = raw.indexOf(RegExp(r'[?#]'));
  return p.posix.normalize(
    p.posix.join(
      p.posix.dirname(edge.source.documentPath),
      cut < 0 ? raw : raw.substring(0, cut),
    ),
  );
}

/// Sorted decoded outside-bundle paths that `path-targets-exist` could query.
/// This pure superset covers every field the builtin accepts, independently of
/// Profile selection/configuration; body links and prose/URLs are excluded.
/// Hosts may observe existence during capture and inject those retained values
/// through `ProfileValidator.outsideBundleExists` without later disk reads.
Set<String> externalPathTargets(OkfBundle bundle) {
  final paths = <String>{};
  for (final edge in OkfGraph.fromBundle(bundle).edges) {
    if (edge.origin == OkfGraphEdgeOrigin.bodyLink) continue;
    resolvePathTarget(
      edge,
      inBundle: (_) => false,
      outsideBundleExists: (relative) {
        paths.add(relative);
        return false;
      },
    );
  }
  return Set.unmodifiable(paths.toList()..sort());
}
