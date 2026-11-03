// Portable: what a reader asks of a project's knowledge. The native
// platform answers through okf and Wayfinder; tests answer from memory.
import 'dart:async';

import 'knowledge_models.dart';

/// The knowledge bundles of one project root, read-only.
///
/// A [snapshot] sees the files as they are on disk now. [concept] and
/// [graph] reuse what the last snapshot of their bundle read, so opening a
/// concept or refocusing the graph reads no more than it must.
abstract interface class KnowledgeProject {
  /// The project's absolute root.
  String get root;

  /// Every bundle, and for [bundle] alone its validation, concepts and
  /// link graph ([focus] and [depth] as [graph] takes them).
  /// Without [bundle], or when the project no longer has it, the snapshot
  /// describes [preferredKnowledgeBundle].
  Future<KnowledgeProjectSnapshot> snapshot({
    String? bundle,
    String? focus,
    int depth = 2,
  });

  Future<KnowledgeConcept> concept({String? bundle, required String id});

  /// The link graph of [bundle]; with [focus], only the concepts within
  /// [depth] links of it.
  Future<KnowledgeGraph> graph({
    required String bundle,
    String? focus,
    int depth = 2,
  });

  /// Whether semantic search is available here.
  bool get canSearch;

  Future<KnowledgeSearchResult> search(
    String query, {
    String? bundle,
    int limit = 12,
    KnowledgeCancellation? cancel,
  });

  /// Brings the saved search index of [bundle], or every bundle, up to date.
  Stream<KnowledgeIndexProgress> index({
    String? bundle,
    bool force = false,
    KnowledgeCancellation? cancel,
  });

  Future<List<KnowledgeBundleIndexStatus>> indexStatus({String? bundle});

  /// Forgets what the project read.
  Future<void> close();
}

/// The local embedding model semantic search needs.
abstract interface class KnowledgeSearchModel {
  Future<KnowledgeModelState> status();

  /// Downloads and verifies the model [consent] names.
  Stream<KnowledgeModelProgress> install(
    KnowledgeModelConsent consent, {
    KnowledgeCancellation? cancel,
  });
}

/// Stops work a caller no longer waits for.
final class KnowledgeCancellation {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes once [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
