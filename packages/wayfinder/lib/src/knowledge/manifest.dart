import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'captured_project.dart';

/// Computes the canonical inventory-manifest fingerprint used by retained adapters.
/// [files] contributes the same file identity as the snapshot revision;
/// [bundles] contains (bundle identity, project-relative bundle path).
String knowledgeManifestFingerprint({
  required Iterable<KnowledgeCapturedFile> files,
  required Iterable<(String, String)> bundles,
}) {
  final fileRows = [
    for (final f in files) jsonEncode(knowledgeFileIdentity(f)),
  ];
  final bundleRows = [
    for (final b in bundles) jsonEncode([b.$1, b.$2]),
  ];
  fileRows.sort();
  bundleRows.sort();
  return sha256
      .convert(
        utf8.encode('[[${bundleRows.join(',')}],[${fileRows.join(',')}]]'),
      )
      .toString();
}
