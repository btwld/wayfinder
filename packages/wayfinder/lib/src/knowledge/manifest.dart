import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes the canonical byte-manifest fingerprint used by retained adapters.
/// [files] contains (bundle identity or null, relative path, SHA-256 digest);
/// [bundles] contains (bundle identity, project-relative bundle path).
String knowledgeManifestFingerprint({
  required Iterable<(String?, String, String)> files,
  required Iterable<(String, String)> bundles,
}) {
  final fileRows = [
    for (final f in files) [f.$1, f.$2, f.$3],
  ];
  final bundleRows = [
    for (final b in bundles) [b.$1, b.$2],
  ];
  fileRows.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  bundleRows.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  return sha256
      .convert(utf8.encode(jsonEncode([bundleRows, fileRows])))
      .toString();
}
