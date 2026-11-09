import 'dart:convert';

import 'package:okf/okf_io.dart';

import '../../../knowledge.dart';
import '../../bundle_file_kind.dart';
import '../../path_targets.dart';

/// Builds an in-memory OKF load from retained bytes without I/O. Malformed
/// Markdown/UTF-8 throws `invalidContent`. The sentinel root requires an explicit
/// external-observation callback when passed to `ProfileValidator`; it must never
/// become a filesystem lookup. Nested coordination locks remain outside OKF.
OkfBundleLoadResult buildOkfBundle(KnowledgeRetainedBundle retained) {
  final documents = <String, OkfDocument>{};
  final indexes = <String, String>{};
  final logs = <String, String>{};
  final assets = <String>[];
  // Match OKF's loader without removing protocol files from browsing.
  final files = retained.files.where(
    (f) => f.path.split('/').last != okfBundleLockFileName,
  );
  for (final file in files) {
    try {
      switch (classifyBundleFile(file.path)) {
        case BundleFileKind.asset:
          assets.add(file.path);
        case BundleFileKind.indexDocument:
          indexes[file.path] = utf8.decode(file.bytes);
        case BundleFileKind.logDocument:
          logs[file.path] = utf8.decode(file.bytes);
        case BundleFileKind.concept:
          OkfConceptId.fromDocumentPath(file.path);
          documents[file.path] = OkfDocument.parse(
            utf8.decode(file.bytes),
            sourcePath: file.path,
          );
      }
    } on FormatException {
      throw KnowledgeFailure(
        KnowledgeFailureCode.invalidContent,
        'buildOkfBundle',
        'Cannot load a partial or malformed captured bundle.',
        path: file.path,
      );
    }
  }
  return OkfBundleLoadResult(
    rootPath: retainedBundleRoot,
    bundle: OkfBundle.fromDocuments(
      documents,
      indexes: indexes,
      logs: logs,
      assets: assets,
    ),
    documents: documents,
    indexes: indexes,
    logs: logs,
    assets: assets,
    report: OkfReport(findings: const []),
  );
}
