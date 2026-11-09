import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'captured_project.dart';
import 'reader.dart';

/// A host's assessment of one exact project capture, never an implicit PASS.
final class KnowledgeAssessmentResult<T> {
  /// Associates [value] with the project and revision supplied to the assessor.
  const KnowledgeAssessmentResult({
    required this.projectId,
    required this.revision,
    required this.value,
  });

  /// Host-owned project identity.
  final String projectId;

  /// Revision of the assessed retained bytes and projections.
  final String revision;

  /// Host-defined assessment, including any unavailable/incomplete outcome.
  final T value;
}

/// Optional capability; existing third-party snapshot implementations need not
/// implement it. Retained-capture backends provide it without enabling validation.
abstract interface class KnowledgeSnapshotAssessmentSource {
  /// Runs explicitly requested work against retained immutable input. Release,
  /// close and revocation prevent late publication; release/close drain work.
  /// Hosts own execution bounds, Profile selection and cancellation of executors.
  Future<KnowledgeAssessmentResult<T>> assess<T>(
    FutureOr<T> Function(KnowledgeCapture capture) assessor, {
    KnowledgeCancellation? cancel,
  });
}

/// Optional assessment and manifest access without extending the base interface.
extension KnowledgeSnapshotAssessment on KnowledgeProjectSnapshot {
  /// SHA-256 of sorted file addresses/digests and bundle identities/paths.
  /// Independent of semantic projection and inventory enumeration order.
  String get manifestFingerprint => knowledgeManifestFingerprint(
    files: [for (final f in files) (f.handle.bundle, f.handle.path, f.digest)],
    bundles: [for (final b in bundles) (b.id, b.summary.path)],
  );

  /// Runs only when requested. Unsupported backends fail explicitly; no result
  /// is cached. Hosts may cache by project, revision and assessment inputs.
  Future<KnowledgeAssessmentResult<T>> assess<T>(
    FutureOr<T> Function(KnowledgeCapture capture) assessor, {
    KnowledgeCancellation? cancel,
  }) {
    final source = this;
    if (source is KnowledgeSnapshotAssessmentSource) {
      return (source as KnowledgeSnapshotAssessmentSource).assess<T>(
        assessor,
        cancel: cancel,
      );
    }
    return Future.error(
      KnowledgeFailure(
        KnowledgeFailureCode.unavailable,
        'assess',
        'This snapshot does not support retained-input assessment.',
      ),
    );
  }
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
