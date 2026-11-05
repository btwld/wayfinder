import 'dart:io';

import 'package:path/path.dart' as p;

import 'exception.dart';

/// Resolves all readable configured roots before selecting any of them.
///
/// An explicitly unselected missing root is tolerated. Every readable root
/// must stay in the project and be disjoint, so selecting one bundle cannot
/// hide an alias overlap in the same configuration.
Future<Map<String, String>> resolveConfiguredBundleRoots(
  String projectRoot,
  Iterable<String> paths, {
  Iterable<String>? selected,
}) async {
  final root = await Directory(projectRoot).resolveSymbolicLinks();
  final required = selected?.toSet();
  final roots = <String, String>{};
  for (final path in paths) {
    final String real;
    try {
      real = await Directory(p.join(root, path)).resolveSymbolicLinks();
    } on FileSystemException {
      if (required != null && !required.contains(path)) continue;
      throw WayfinderException(
        'bundle-missing',
        'Configured bundle $path does not exist or is unreadable.',
      );
    }
    if (!p.isWithin(root, real)) {
      throw WayfinderException(
        'bundle-escapes',
        'Configured bundle leaves the project: $path.',
      );
    }
    if (roots.values.any(
      (other) =>
          p.equals(other, real) ||
          p.isWithin(other, real) ||
          p.isWithin(real, other),
    )) {
      throw const WayfinderException(
        'config-invalid',
        'Configured bundles overlap after resolving symlinks.',
      );
    }
    roots[path] = real;
  }
  return roots;
}
