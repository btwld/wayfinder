import '../okf/knowledge_input_diagnostic.dart';
import 'project_search.dart' show KnowledgeCitation;

/// Counts and location of a completed local indexing operation.
class WayfinderIndexResult {
  const WayfinderIndexResult({
    required this.bundle,
    required this.index,
    required this.embeddedChunks,
    required this.removedChunks,
    required this.writtenChunks,
    required this.elapsedMs,
    this.current = false,
    this.warnings = const [],
  });

  final List<KnowledgeInputDiagnostic> warnings;

  /// The canonical bundle root.
  final String bundle;

  /// The index directory of this bundle and the store's configuration.
  final String index;
  final int embeddedChunks;
  final int removedChunks;
  final int writtenChunks;
  final int elapsedMs;

  /// The saved index already matched the bundle; the model was not loaded.
  final bool current;

  /// The CLI and MCP JSON contract, independent of field access.
  Map<String, Object?> toJson() => {
    'bundle': bundle,
    'index': index,
    'embeddedChunks': embeddedChunks,
    'removedChunks': removedChunks,
    'writtenChunks': writtenChunks,
    'elapsedMs': elapsedMs,
    'current': current,
    'warnings': [for (final warning in warnings) warning.toJson()],
  };
}

/// The state of a bundle's saved index for the store's configuration and
/// encoder, from `WayfinderKnowledgeStore.status`.
sealed class KnowledgeIndexStatus {
  const KnowledgeIndexStatus();
}

/// No index was saved for this configuration and encoder.
final class KnowledgeIndexMissing extends KnowledgeIndexStatus {
  const KnowledgeIndexMissing();
}

/// The saved index matches the bundle; indexing has nothing to do and
/// search can use it.
final class KnowledgeIndexCurrent extends KnowledgeIndexStatus {
  const KnowledgeIndexCurrent({this.warnings = const []});

  /// The input recoveries the saved index recorded.
  final List<KnowledgeInputDiagnostic> warnings;
}

/// The bundle changed since it was indexed; search refuses the index until
/// it is indexed again.
final class KnowledgeIndexStale extends KnowledgeIndexStatus {
  const KnowledgeIndexStale(this.changedPaths);

  /// Bundle-relative paths added, removed or edited since, sorted.
  final List<String> changedPaths;
}

/// The saved index cannot be used and indexing replaces it.
final class KnowledgeIndexIncompatible extends KnowledgeIndexStatus {
  const KnowledgeIndexIncompatible(this.reason);

  /// Why, as a sentence.
  final String reason;
}

/// An operation is indexing the bundle, or forgetting its index, right now.
/// Searches still read the last published generation, which [previous]
/// describes; with [StaleIndexPolicy.serveWhileRefreshing] they serve it
/// even when it is stale.
final class KnowledgeIndexRefreshing extends KnowledgeIndexStatus {
  const KnowledgeIndexRefreshing(this.previous);

  /// The last published generation against the bundle as it is now:
  /// never another [KnowledgeIndexRefreshing].
  final KnowledgeIndexStatus previous;
}

/// What a search does with a saved index that no longer matches its
/// bundle.
enum StaleIndexPolicy {
  /// Refuse it with `index-stale`, whatever else is running. A search with
  /// this policy never checks for a refresh.
  refuse,

  /// While another operation refreshes the bundle's index, serve the last
  /// published generation: the result adds a `refresh-in-progress` notice,
  /// and a `source-changed` notice and [KnowledgeCitation.sourceChanged] for
  /// files edited since that generation was built. With no refresh running,
  /// refuse a stale index as [refuse] does.
  serveWhileRefreshing,
}

/// A step of `WayfinderKnowledgeStore.index`.
enum IndexPhase {
  /// Hashing the bundle's files to compare them with the saved index.
  scanning,

  /// Opening the encoder, which may load a model, then loading the bundle
  /// and fitting its passages to the encoder.
  loading,

  /// Embedding passages; [IndexProgress.completed] of [IndexProgress.total].
  embedding,

  /// Writing the completed generation, making it current, and deleting
  /// generations superseded long enough ago.
  publishing,
}

/// An event `WayfinderKnowledgeStore.index` reports while it runs. A
/// current index reports only [IndexPhase.scanning].
final class IndexProgress {
  const IndexProgress(this.phase, {this.completed = 0, this.total = 0});

  final IndexPhase phase;

  /// Inputs embedded so far, in [IndexPhase.embedding].
  final int completed;

  /// Inputs this run embeds, in [IndexPhase.embedding].
  final int total;

  @override
  String toString() => phase == IndexPhase.embedding
      ? 'IndexProgress(${phase.name} $completed/$total)'
      : 'IndexProgress(${phase.name})';
}

/// One index directory `WayfinderKnowledgeStore.prune` removed.
final class KnowledgePrunedIndex {
  const KnowledgePrunedIndex({
    required this.directory,
    required this.root,
    required this.reason,
  });

  /// The removed index directory.
  final String directory;

  /// The bundle root it indexed, when it recorded one.
  final String? root;

  /// `missing-root` when that bundle no longer exists, or
  /// `other-configuration` when it was built for another configuration or
  /// encoder and went unused for the prune's period.
  final String reason;
}

/// What `WayfinderKnowledgeStore.prune` removed and what it left in use.
final class KnowledgePruneResult {
  const KnowledgePruneResult({
    this.removed = const [],
    this.busy = const [],
    this.projectLocks = const [],
    this.downloads = const [],
  });

  final List<KnowledgePrunedIndex> removed;

  /// Index directories a running command held, left for a later prune.
  final List<String> busy;

  /// The `get` lock files of project roots that no longer exist, deleted.
  final List<String> projectLocks;

  /// Temporary files of model downloads abandoned at least a day ago,
  /// deleted.
  final List<String> downloads;
}
