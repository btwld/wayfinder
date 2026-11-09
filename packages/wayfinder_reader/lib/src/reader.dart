import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'knowledge_models.dart';

/// Stable failures are distinct from content findings and validation verdicts.
enum KnowledgeFailureCode {
  denied,
  notFound,
  sourceChanged,
  revisionUnavailable,
  invalidContent,
  graphRefused,
  tooLarge,
  cancelled,
  closed,
  unavailable,
}

final class KnowledgeFailure implements Exception {
  KnowledgeFailure(this.code, this.operation, this.message, {this.path});
  final KnowledgeFailureCode code;
  final String operation;
  final String message;
  final String? path;
  @override
  String toString() => '$operation: $message';
}

/// Validated opaque identity/revision; neither is a filesystem location.
String knowledgeIdentifier(String value, String name) {
  if (value.trim().isEmpty || value.contains(RegExp(r'[\x00-\x1f\x7f-\x9f]'))) {
    throw ArgumentError.value(value, name, 'Expected a nonblank identifier');
  }
  return value;
}

/// POSIX relative resource address. Never decoded or normalized into permission.
String knowledgeRelativePath(String value) {
  if (value.isEmpty ||
      value.contains(RegExp(r'[\\:\x00-\x1f\x7f-\x9f]')) ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(value, 'path', 'Expected a safe relative path');
  }
  return value;
}

/// A file address in one exact snapshot. A null bundle means project config.
final class KnowledgeResourceHandle {
  KnowledgeResourceHandle({
    required String project,
    required String revision,
    String? bundle,
    required String path,
  }) : project = knowledgeIdentifier(project, 'project'),
       revision = knowledgeIdentifier(revision, 'revision'),
       bundle = bundle == null ? null : knowledgeIdentifier(bundle, 'bundle'),
       path = knowledgeRelativePath(path);
  final String project;
  final String revision;
  final String? bundle;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeResourceHandle &&
      project == other.project &&
      revision == other.revision &&
      bundle == other.bundle &&
      path == other.path;
  @override
  int get hashCode => Object.hash(project, revision, bundle, path);
}

/// Complete permitted inventory, including unparseable Markdown and attachments.
final class KnowledgeResourceEntry {
  KnowledgeResourceEntry({
    required this.handle,
    required this.sizeBytes,
    required this.digest,
    this.mediaType,
  }) {
    if (sizeBytes < 0) throw ArgumentError.value(sizeBytes, 'sizeBytes');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw ArgumentError.value(digest, 'digest', 'Expected SHA-256');
    }
  }
  final KnowledgeResourceHandle handle;
  final int sizeBytes;
  final String digest;
  final String? mediaType;
  String get name => handle.path.split('/').last;
}

/// Verified immutable bytes; strict UTF-8 decoding never invents replacement text.
final class KnowledgeSourceBytes {
  KnowledgeSourceBytes({required this.entry, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (this.bytes.length != entry.sizeBytes ||
        sha256.convert(this.bytes).toString() != entry.digest) {
      throw ArgumentError('Bytes do not match the captured entry.');
    }
  }
  final KnowledgeResourceEntry entry;
  final Uint8List bytes;
  String get text => utf8.decode(bytes);
}

/// Browsing does not imply assessment. Hosts must explicitly request any
/// optional assessment; this value is never a PASS.
final class KnowledgeValidationUnavailable {
  KnowledgeValidationUnavailable(String reason)
    : reason = knowledgeIdentifier(reason, 'reason');
  final String reason;
}

final class KnowledgeCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void check(String operation) {
    if (isCancelled) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.cancelled,
        operation,
        'The request was cancelled.',
      );
    }
  }
}

/// Hosts own projects; controllers borrow them. Each refresh returns a new lease.
abstract interface class KnowledgeProject {
  String get id;

  /// Revocation is synchronous from the backend's perspective. Subscribers must
  /// clear retained presentation, not fall back as on a transient refresh error.
  Stream<void> get revocations;
  Future<KnowledgeProjectSnapshot> refresh({KnowledgeCancellation? cancel});

  /// Rejects new work immediately, invalidates leases and drains accepted work.
  Future<void> close();
}

abstract interface class KnowledgeProjectSnapshot {
  String get projectId;
  String get revision;
  List<KnowledgeBundleSnapshot> get bundles;
  List<KnowledgeResourceEntry> get files;
  KnowledgeBundleSnapshot bundle(String id);
  Future<KnowledgeSourceBytes> read(
    KnowledgeResourceHandle handle, {
    int maxBytes = 16 * 1024 * 1024,
    KnowledgeCancellation? cancel,
  });

  /// Invalidates only this lease and its bundle views; idempotent and draining.
  Future<void> release();
}

abstract interface class KnowledgeBundleSnapshot {
  String get id;

  /// Opaque revision of this view. Retained-capture backends currently use the
  /// whole project revision: another bundle/config change can invalidate this
  /// value too. Do not assume independent per-bundle versioning.
  String get revision;
  KnowledgeBundleSummary get summary;
  List<KnowledgeResourceEntry> get files;
  List<KnowledgeConceptSummary> get concepts;
  Future<KnowledgeConcept> concept(String id, {KnowledgeCancellation? cancel});
  Future<KnowledgeGraph> graph({KnowledgeCancellation? cancel});
  KnowledgeValidationUnavailable get validation;
}
