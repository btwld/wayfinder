import 'dart:io';

import 'package:path/path.dart' as p;

/// The search `WayfinderProjectConfig.bind` makes for a bundle's
/// `wayfinder.json` without a configuration path: [found] is the file it
/// binds, or null; [searched] is each `wayfinder.json` path it looked at, in
/// order, ending with [found] when there is one.
///
/// The search starts in the parent directory of [bundlePath] and climbs
/// towards the filesystem root. [projectRoot] bounds it: it climbs the same
/// directories but looks only in those whose real path is [projectRoot] or
/// inside it, and stops at [projectRoot] or at the first directory above it.
Future<({File? found, List<String> searched})> searchProjectConfig(
  String bundlePath, {
  String? projectRoot,
}) async {
  final searched = <String>[];
  final ceiling = projectRoot == null ? null : await _realPath(projectRoot);
  var directory = p.dirname(File(bundlePath).absolute.path);
  while (true) {
    var read = true;
    var last = false;
    if (ceiling != null) {
      final real = await _realPath(directory);
      // Read only inside the project; end at its root or above it.
      read = p.equals(real, ceiling) || p.isWithin(ceiling, real);
      last = p.equals(real, ceiling) || p.isWithin(real, ceiling);
    }
    if (read) {
      final file = File(p.join(directory, 'wayfinder.json'));
      searched.add(file.path);
      if (await file.exists()) return (found: file, searched: searched);
    }
    final parent = p.dirname(directory);
    if (last || parent == directory) return (found: null, searched: searched);
    directory = parent;
  }
}

/// [path] absolute, with its symbolic links resolved: the segments that do
/// not exist, or are links that do not resolve, are appended to the real
/// path of their nearest ancestor that does.
Future<String> _realPath(String path) async {
  final absolute = Directory(path).absolute.path;
  final missing = <String>[];
  var existing = absolute;
  while (true) {
    try {
      return p.normalize(
        p.joinAll([
          await Directory(existing).resolveSymbolicLinks(),
          ...missing,
        ]),
      );
    } on FileSystemException {
      final parent = p.dirname(existing);
      if (parent == existing) return p.normalize(absolute);
      missing.insert(0, p.basename(existing));
      existing = parent;
    }
  }
}
