// Portable: a reader's view of project knowledge. The native platform
// fills these from okf and Wayfinder; widget tests build them directly.
import 'package:meta/meta.dart' show immutable;

/// A concept's trust tier, as okf derives it from its stamps.
enum KnowledgeTrust { unverified, machineConfirmed, humanReviewed }

/// What a link's target resolved to, as okf's graph reports it.
enum KnowledgeLinkResolution {
  resolvedConcept,
  resolvedAsset,
  external,
  descriptor,
  unresolved,
  invalid,
}

/// Where a link comes from: okf's link origins, plus Wayfinder's typed
/// `relationships` entries.
enum KnowledgeLinkOrigin {
  body('body'),
  resource('resource'),
  sourceResource('sources.resource'),
  computation('computation'),
  executorResource('executor.resource'),
  attesterResource('attester.resource'),
  relationships('relationships');

  const KnowledgeLinkOrigin(this.wireValue);
  final String wireValue;
}

/// One bundle the project's `wayfinder.json` binds, or its conventional
/// `knowledge/` folder.
@immutable
final class KnowledgeBundleSummary {
  const KnowledgeBundleSummary({
    required this.name,
    required this.path,
    required this.conceptCount,
    this.revision = 0,
  });

  final String name;

  /// The bundle's path relative to the project root; never the root itself,
  /// which Wayfinder refuses as a bundle.
  final String path;
  final int conceptCount;

  /// Compact display/cache fingerprint. Reader leases expose the full opaque
  /// content revision; do not use this integer as a resource address.
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeBundleSummary &&
      name == other.name &&
      path == other.path &&
      conceptCount == other.conceptCount &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(name, path, conceptCount, revision);
}

@immutable
final class KnowledgeConceptSummary {
  const KnowledgeConceptSummary({
    required this.bundle,
    required this.id,
    required this.path,
    required this.title,
    this.description,
    required this.type,
    this.tags = const [],
  });

  final String bundle;

  /// The concept file's bundle-relative path without `.md`.
  final String id;

  /// The concept file's path relative to the project root.
  final String path;
  final String title;
  final String? description;

  /// The concept type; empty when it has none.
  final String type;
  final List<String> tags;
}

/// One entry of a concept's `sources`.
@immutable
final class KnowledgeSource {
  const KnowledgeSource({
    this.id,
    this.resource,
    this.title,
    this.author,
    this.path,
  });

  final String? id;

  /// The resource as written: a URL or a bundle path.
  final String? resource;
  final String? title;
  final String? author;

  /// The file the resource names, relative to the project root, when it is
  /// in the bundle.
  final String? path;
}

/// One typed link of a concept's `relationships`.
@immutable
final class KnowledgeConceptRelationship {
  const KnowledgeConceptRelationship({
    this.relationship,
    required this.target,
    required this.resolution,
    this.conceptId,
    this.path,
  });

  final String? relationship;

  /// The target as written.
  final String target;
  final KnowledgeLinkResolution resolution;
  final String? conceptId;

  /// The target file relative to the project root, when it is in the bundle.
  final String? path;
}

/// A concept that links to the one read.
@immutable
final class KnowledgeBacklink {
  const KnowledgeBacklink({
    required this.conceptId,
    required this.path,
    required this.title,
    required this.origin,
    this.relationship,
  });

  final String conceptId;
  final String path;
  final String title;
  final KnowledgeLinkOrigin origin;
  final String? relationship;
}

/// Who or what acted on a concept, and when: its `generated` stamp or one
/// of its `verified` events.
@immutable
final class KnowledgeConceptStamp {
  const KnowledgeConceptStamp({this.by, this.at, this.written});

  /// The actor as written, such as `openai/codex` or `human:ada`.
  final String? by;

  /// The instant, when it parses.
  final DateTime? at;

  /// The instant as written, for a tooltip.
  final String? written;
}

/// What an Attested Computation is: a recipe the bundle keeps, never its
/// result. okf models the contract and runs nothing, and neither does this
/// package.
@immutable
final class KnowledgeComputation {
  const KnowledgeComputation({this.runtime, this.reads = const []});

  /// The runtime that defines how it runs, such as `python`.
  final String? runtime;

  /// What the recipe reads: the files its `computation`, `executor` and
  /// `attester` name, then the documents its body links to.
  final List<KnowledgeComputationInput> reads;

  /// How many concepts of the bundle it reads.
  int get conceptCount => reads.where((read) => read.conceptId != null).length;
}

/// One thing an Attested Computation reads.
@immutable
final class KnowledgeComputationInput {
  const KnowledgeComputationInput({
    required this.target,
    required this.origin,
    required this.resolution,
    this.conceptId,
    this.path,
  });

  /// The target as written.
  final String target;
  final KnowledgeLinkOrigin origin;
  final KnowledgeLinkResolution resolution;
  final String? conceptId;

  /// The target file relative to the project root, when it is in the bundle.
  final String? path;
}

/// One concept at its captured source revision.
@immutable
final class KnowledgeConcept {
  const KnowledgeConcept({
    required this.bundle,
    required this.id,
    required this.path,
    required this.citation,
    required this.title,
    this.description,
    required this.type,
    required this.status,
    this.tags = const [],
    required this.trust,
    required this.frontmatter,
    this.sources = const [],
    this.relationships = const [],
    this.backlinks = const [],
    this.generated,
    this.verified = const [],
    this.staleAfter,
    this.computation,
    required this.body,
    required this.lineCount,
  });

  final String bundle;
  final String id;
  final String path;

  /// The body lines in the file, as `path:start-end`; the whole file when
  /// the body is empty.
  final String citation;
  final String title;
  final String? description;
  final String type;
  final String status;
  final List<String> tags;
  final KnowledgeTrust trust;
  final Map<String, Object?> frontmatter;
  final List<KnowledgeSource> sources;
  final List<KnowledgeConceptRelationship> relationships;
  final List<KnowledgeBacklink> backlinks;

  /// Who or what produced the current content, and when.
  final KnowledgeConceptStamp? generated;

  /// The events that confirmed it, as written.
  final List<KnowledgeConceptStamp> verified;

  /// The instant from which the concept is stale, from OKF's
  /// `stale_after`, when it parses: due for review then. The reader
  /// compares it with the controller's clock; okf reports no finding.
  final DateTime? staleAfter;

  /// The recipe, when the concept is an Attested Computation.
  final KnowledgeComputation? computation;
  final String body;
  final int lineCount;
}

@immutable
final class KnowledgeGraphNode {
  const KnowledgeGraphNode({
    required this.id,
    required this.path,
    required this.title,
    required this.type,
  });

  final String id;
  final String path;
  final String title;
  final String type;
}

@immutable
final class KnowledgeGraphEdge {
  const KnowledgeGraphEdge({
    required this.source,
    required this.target,
    required this.origin,
    required this.resolution,
    this.relationship,
    this.path,
  });

  final String source;

  /// The target concept id, or the target as written when it is no concept.
  final String target;
  final KnowledgeLinkOrigin origin;
  final KnowledgeLinkResolution resolution;
  final String? relationship;
  final String? path;
}

@immutable
final class KnowledgeGraph {
  const KnowledgeGraph({
    required this.bundle,
    required this.nodes,
    required this.edges,
  });

  final String bundle;
  final List<KnowledgeGraphNode> nodes;
  final List<KnowledgeGraphEdge> edges;
}
