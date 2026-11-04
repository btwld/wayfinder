import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

/// Checks a path-valued field using the loaded inventory inside the bundle,
/// and optional disk lookup only for relative paths outside it.
///
/// URLs and prose descriptors are not missing paths. Explicit `/`, `./` and
/// `../` prefixes remain paths even when the graph classified whitespace as
/// prose. Percent decoding follows OKF; malformed escapes, separators within
/// decoded segments and bundle-root parent escapes are missing. A present
/// internal target returns its decoded bundle-relative path for display.
({bool missing, String? bundlePath}) resolvePathTarget(
  OkfGraphEdge edge, {
  required bool Function(String path) inBundle,
  String? rootPath,
}) {
  const notPath = (missing: false, bundlePath: null);
  const missing = (missing: true, bundlePath: null);
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
        ? (missing: false, bundlePath: edge.source.documentPath)
        : missing;
  }
  final decoded = <String>[];
  for (final segment in target.split('/')) {
    final value = _decodeSegment(segment);
    if (value == null ||
        value.contains('/') ||
        value.contains(r'\') ||
        value.runes.any((rune) => rune < 32 || rune == 127)) {
      return missing;
    }
    decoded.add(value);
  }
  final directory = target.startsWith('/')
      ? '.'
      : p.posix.dirname(edge.source.documentPath);
  final relative = p.posix.normalize(
    p.posix.joinAll([...directory.split('/'), ...decoded]),
  );
  final outside = relative == '..' || relative.startsWith('../');
  if (!outside) {
    return inBundle(relative)
        ? (missing: false, bundlePath: relative)
        : missing;
  }
  if (target.startsWith('/')) return missing;
  // An in-memory caller cannot inspect a relative path outside its inventory.
  if (rootPath == null) return notPath;
  try {
    return (
      missing:
          FileSystemEntity.typeSync(
            p.normalize(p.joinAll([rootPath, ...relative.split('/')])),
          ) ==
          FileSystemEntityType.notFound,
      bundlePath: null,
    );
  } on FileSystemException {
    return missing;
  }
}

// Keep OKF's strict decoding boundary: unescaped Unicode is already text,
// while a malformed percent sequence is never a literal filename fallback.
String? _decodeSegment(String segment) {
  if (!segment.contains('%')) return segment;
  try {
    return Uri.decodeComponent(segment);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}
