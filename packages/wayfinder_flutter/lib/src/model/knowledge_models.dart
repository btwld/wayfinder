// Portable: a reader's view of project knowledge. The native platform
// fills these from okf and Wayfinder; widget tests build them directly.
import 'package:flutter/foundation.dart' show immutable;

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

/// A bundle's validation verdict, as `wayfinder validate` derives it.
enum KnowledgeGate {
  pass('PASS'),
  fail('FAIL'),
  incomplete('INCOMPLETE');

  const KnowledgeGate(this.wireValue);
  final String wireValue;
}

enum KnowledgeFindingSeverity { error, warning, advisory, note }

/// Which check reported a finding: okf, the Profile's rules, or Wayfinder
/// itself (a Profile it could not resolve, for example).
enum KnowledgeFindingSource { okf, profile, engine }

/// Whether a bundle's saved search index matches the bundle.
///
/// Provisional: an index controller with the changed files and counts replaces
/// this, so don't build on it.
enum KnowledgeIndexState { missing, stale, current, refreshing }

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

  /// Which load of the bundle this describes: it changes when the bundle's
  /// files, binding or lock do, and only then.
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

/// The bundle a project reads first: the one named `knowledge`, else the
/// one with the most concepts, the first by path among equals; null when
/// there is none.
KnowledgeBundleSummary? preferredKnowledgeBundle(
  Iterable<KnowledgeBundleSummary> bundles,
) {
  KnowledgeBundleSummary? preferred;
  for (final bundle in bundles) {
    if (bundle.name == 'knowledge' || bundle.path == 'knowledge') return bundle;
    if (preferred == null ||
        bundle.conceptCount > preferred.conceptCount ||
        (bundle.conceptCount == preferred.conceptCount &&
            bundle.path.compareTo(preferred.path) < 0)) {
      preferred = bundle;
    }
  }
  return preferred;
}

/// What one refresh of a project shows, read in one pass over its files.
@immutable
final class KnowledgeProjectSnapshot {
  const KnowledgeProjectSnapshot({
    this.bundles = const [],
    this.validations = const {},
    this.concepts = const [],
    this.graph,
  });

  /// Every bundle of the project, by path.
  final List<KnowledgeBundleSummary> bundles;

  /// The verdicts already reached for bundles a Profile judges, by bundle
  /// path. A bundle without a selected Profile is never here: it looks for
  /// one again through [KnowledgeProject.validation], as does every bundle
  /// still being judged.
  final Map<String, KnowledgeBundleValidation> validations;

  /// The concepts of every bundle.
  final List<KnowledgeConceptSummary> concepts;

  /// The link graph of one bundle, as [KnowledgeProject.snapshot] was asked.
  final KnowledgeGraph? graph;
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

/// One concept as it is on disk now.
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

@immutable
final class KnowledgeFinding {
  const KnowledgeFinding({
    required this.id,
    required this.severity,
    required this.message,
    this.path,
    this.line,
    required this.source,
  });

  /// The rule or check id, such as an okf code or a Profile rule.
  final String id;
  final KnowledgeFindingSeverity severity;
  final String message;

  /// The file relative to the project root, when the finding names one.
  final String? path;
  final int? line;
  final KnowledgeFindingSource source;
}

/// How `wayfinder validate` judges a bundle: its gate, the Profile it
/// used, and every finding.
@immutable
final class KnowledgeBundleValidation {
  const KnowledgeBundleValidation({
    required this.gate,
    this.profileId,
    this.findings = const [],
  });

  final KnowledgeGate gate;

  /// The Profile's id, when one judged the bundle.
  final String? profileId;
  final List<KnowledgeFinding> findings;
}

/// One passage semantic search matched.
@immutable
final class KnowledgeHit {
  const KnowledgeHit({
    required this.citation,
    required this.bundle,
    required this.path,
    required this.lineStart,
    required this.lineEnd,
    required this.text,
    this.conceptId,
    this.title,
    this.sourceChanged = false,
  });

  final String citation;
  final String bundle;
  final String path;
  final int lineStart;
  final int lineEnd;
  final String text;
  final String? conceptId;
  final String? title;

  /// Whether the file changed since the passage was indexed.
  final bool sourceChanged;
}

@immutable
final class KnowledgeSearchNotice {
  const KnowledgeSearchNotice({required this.code, required this.message});
  final String code;
  final String message;
}

@immutable
final class KnowledgeBundleIndexStatus {
  const KnowledgeBundleIndexStatus({required this.bundle, required this.state});
  final String bundle;
  final KnowledgeIndexState state;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeBundleIndexStatus &&
      other.bundle == bundle &&
      other.state == state;

  @override
  int get hashCode => Object.hash(bundle, state);
}

@immutable
final class KnowledgeSearchResult {
  const KnowledgeSearchResult({
    required this.query,
    this.matches = const [],
    this.notices = const [],
    this.index = const [],
  });

  final String query;
  final List<KnowledgeHit> matches;
  final List<KnowledgeSearchNotice> notices;
  final List<KnowledgeBundleIndexStatus> index;
}

/// A step of an index run, for a progress line.
///
/// Provisional, like [KnowledgeIndexState].
@immutable
final class KnowledgeIndexProgress {
  const KnowledgeIndexProgress({required this.bundle, required this.step});
  final String bundle;
  final String step;
}

/// Why a knowledge operation failed, in words a person can act on.
final class KnowledgeException implements Exception {
  const KnowledgeException(this.message, {this.remedy});

  final String message;
  final String? remedy;

  @override
  String toString() => remedy == null ? message : '$message $remedy';
}

/// The local embedding model semantic search needs.
@immutable
final class KnowledgeModelState {
  const KnowledgeModelState({
    required this.model,
    required this.name,
    required this.installed,
    required this.sizeBytes,
    required this.source,
    required this.sha256,
  });

  /// The model's id, such as `arctic-embed-xs-q8_0`.
  final String model;

  /// The model as people know it, such as `Snowflake Arctic Embed XS`.
  final String name;
  final bool installed;
  final int sizeBytes;
  final Uri source;
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeModelState &&
      other.model == model &&
      other.name == name &&
      other.installed == installed &&
      other.sizeBytes == sizeBytes &&
      other.source == source &&
      other.sha256 == sha256;

  @override
  int get hashCode =>
      Object.hash(model, name, installed, sizeBytes, source, sha256);
}

/// A person's agreement to download exactly the model [state] describes.
@immutable
final class KnowledgeModelConsent {
  const KnowledgeModelConsent.to(this.state);
  final KnowledgeModelState state;
}

@immutable
sealed class KnowledgeModelProgress {
  const KnowledgeModelProgress();
}

final class KnowledgeModelDownloading extends KnowledgeModelProgress {
  const KnowledgeModelDownloading({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;
}

final class KnowledgeModelVerifying extends KnowledgeModelProgress {
  const KnowledgeModelVerifying();
}

final class KnowledgeModelInstalled extends KnowledgeModelProgress {
  const KnowledgeModelInstalled();
}
