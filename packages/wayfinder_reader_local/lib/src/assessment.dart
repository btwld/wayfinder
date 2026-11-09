import 'dart:async';
import 'dart:convert';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

/// Retained inputs for host-owned Profile selection and validation.
/// No resolver, fetch, file read or model is invoked by this input.
final class KnowledgeBundleAssessmentInput {
  KnowledgeBundleAssessmentInput._(this.capture, this.bundleId, this.loaded);

  /// Exact immutable project inputs, including captured configuration and lock.
  /// Select Profiles against these bytes, not a newer configuration on disk.
  final KnowledgeCapture capture;

  /// Host identity of the assessed bundle.
  final String bundleId;

  /// In-memory OKF load of the retained bundle files. Its synthetic root is
  /// for diagnostics only; use [validate] to prevent live external-target I/O.
  final OkfBundleLoadResult loaded;

  /// Validates retained bytes against a host-selected Profile. Hosts may run
  /// this in an isolate. Selection and execution bounds remain host policy.
  ///
  /// External path observations are not captured by this backend. If a rule
  /// needs one, throws [KnowledgeFailureCode.unavailable], never guesses PASS
  /// or reads live disk. Malformed Markdown refuses input preparation rather
  /// than validating a partial bundle. No validation is performed implicitly.
  ProfileValidationResult validate(ProfileSelection selection) =>
      ProfileValidator(
        outsideBundleExists: (relative) => throw KnowledgeFailure(
          KnowledgeFailureCode.unavailable,
          'assess',
          'The snapshot did not capture this external path observation.',
          path: relative,
        ),
      ).validateLoaded(loaded, selection);
}

/// Lease-bound assessment using core's in-memory validator.
extension KnowledgeBundleAssessment on KnowledgeProjectSnapshot {
  /// Prepares only retained bytes, then invokes [assessor]. The callback may
  /// select a Profile from [KnowledgeBundleAssessmentInput.capture] and run
  /// `Isolate.run(() => input.validate(selection))`. Its result carries the
  /// displayed snapshot revision; released/revoked leases reject late results.
  /// Profile fetching, retries and executor cancellation belong to the host.
  Future<KnowledgeAssessmentResult<T>> assessBundle<T>(
    String bundleId,
    FutureOr<T> Function(KnowledgeBundleAssessmentInput input) assessor, {
    KnowledgeCancellation? cancel,
  }) => assess((capture) {
    if (capture.assessmentUnavailableReason case final reason?) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.unavailable,
        'assess',
        reason,
      );
    }
    final bundle = capture.bundles.where((b) => b.id == bundleId).firstOrNull;
    if (bundle == null) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.notFound,
        'assess',
        'The bundle is not in this snapshot.',
      );
    }
    final documents = <String, OkfDocument>{};
    final indexes = <String, String>{};
    final logs = <String, String>{};
    final assets = <String>[];
    // Match OKF's loader without removing protocol files from browsing.
    final files =
        capture.files
            .where(
              (f) =>
                  f.bundle == bundleId &&
                  p.posix.basename(f.path) != okfBundleLockFileName,
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (!file.path.endsWith('.md')) {
        assets.add(file.path);
        continue;
      }
      try {
        final source = utf8.decode(file.bytes);
        switch (p.posix.basename(file.path)) {
          case 'index.md':
            indexes[file.path] = source;
          case 'log.md':
            logs[file.path] = source;
          default:
            OkfConceptId.fromDocumentPath(file.path);
            documents[file.path] = OkfDocument.parse(
              source,
              sourcePath: file.path,
            );
        }
      } on FormatException {
        throw KnowledgeFailure(
          KnowledgeFailureCode.invalidContent,
          'assess',
          'Cannot assess a partial or malformed captured bundle.',
          path: file.path,
        );
      }
    }
    final loaded = OkfBundleLoadResult(
      rootPath: p.absolute('__wayfinder_snapshot__', bundle.summary.path),
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
    return assessor(
      KnowledgeBundleAssessmentInput._(capture, bundleId, loaded),
    );
  }, cancel: cancel);
}
