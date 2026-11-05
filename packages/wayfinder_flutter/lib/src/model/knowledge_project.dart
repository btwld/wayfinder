// Portable: what a reader asks of a project's knowledge. The native
// platform answers through okf and Wayfinder; tests answer from memory.
import 'dart:async';

import 'knowledge_graph_scene.dart';
import 'knowledge_models.dart';

/// The knowledge bundles of one project root, read-only. The project is
/// the scope: every bundle shows, and search spans them all.
///
/// A [snapshot] sees the files as they are on disk now. [validation],
/// [concept] and [graph] reuse what the last snapshot of their bundle read,
/// so opening a concept or refocusing the graph reads no more than it must.
abstract interface class KnowledgeProject {
  /// The project's absolute root.
  String get root;

  /// Every bundle and its concepts, the validations already judged, and the
  /// link graph of [graphBundle] ([focus] and [depth] as [graph] takes
  /// them). Without [graphBundle], or when the project no longer has it,
  /// the graph is [preferredKnowledgeBundle]'s.
  Future<KnowledgeProjectSnapshot> snapshot({
    String? graphBundle,
    String? focus,
    int depth = knowledgeGraphDefaultDepth,
  });

  /// How the Profile judges [bundle] as the last snapshot read it.
  Future<KnowledgeBundleValidation> validation({required String bundle});

  Future<KnowledgeConcept> concept({
    required String bundle,
    required String id,
  });

  /// The link graph of [bundle]; with [focus], only the concepts within
  /// [depth] links of it.
  ///
  /// [depth] is [clampKnowledgeGraphDepth], 1 to 3, and defaults to
  /// [knowledgeGraphDefaultDepth], the same range and default as
  /// [KnowledgeGraphQuery].
  Future<KnowledgeGraph> graph({
    required String bundle,
    String? focus,
    int depth = knowledgeGraphDefaultDepth,
  });

  /// Whether semantic search is available here.
  bool get canSearch;

  /// Passages of every bundle, ranked together.
  Future<KnowledgeSearchResult> search(
    String query, {
    int limit = 12,
    KnowledgeCancellation? cancel,
  });

  /// Brings the saved search index of every bundle up to date.
  Stream<KnowledgeIndexProgress> index({
    bool force = false,
    KnowledgeCancellation? cancel,
  });

  /// Where the saved search index of each bundle stands.
  Future<List<KnowledgeBundleIndexStatus>> indexStatus();

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
