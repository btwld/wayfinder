import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'reader.dart';

/// Byte-manifest identity independent of semantic projections.
extension KnowledgeSnapshotManifest on KnowledgeProjectSnapshot {
  /// SHA-256 of sorted resource addresses/digests and bundle identities/paths.
  String get manifestFingerprint => knowledgeManifestFingerprint(
    files: [for (final f in files) (f.handle.bundle, f.handle.path, f.digest)],
    bundles: [for (final b in bundles) (b.id, b.summary.path)],
  );
}

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
