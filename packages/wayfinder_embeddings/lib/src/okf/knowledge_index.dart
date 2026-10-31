import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart'
    show ProjectBundle, WayfinderCancellation, throwIfCancelled;
import 'package:wayfinder/wayfinder.dart' show OkfFieldEdge;

import '../embedding/base_embedder.dart';
import '../models/chunk.dart';
import '../models/embedding.dart';
import '../models/search_result.dart';
import '../storage/base_store.dart';
import '../util/similarity.dart';
import 'knowledge_snapshot.dart';

/// Deterministic frontmatter eligibility, independent of retrieval scores.
/// Values within each set use OR, except [requiredTags], which uses AND.
/// Different fields combine with AND. Identifiers are exact and case-sensitive;
/// title/description containment is literal and case-insensitive.
class KnowledgeMetadataFilter {
  KnowledgeMetadataFilter({
    Set<String> tags = const {},
    Set<String> requiredTags = const {},
    Set<String> types = const {},
    Set<String> statuses = const {},
    Set<String> pathPrefixes = const {},
    this.titleContains,
    this.descriptionContains,
  }) : tags = Set.unmodifiable(tags),
       requiredTags = Set.unmodifiable(requiredTags),
       types = Set.unmodifiable(types),
       statuses = Set.unmodifiable(statuses),
       pathPrefixes = Set.unmodifiable(pathPrefixes) {
    for (final value in [
      ...tags,
      ...requiredTags,
      ...types,
      ...statuses,
      ...pathPrefixes,
      ?titleContains,
      ?descriptionContains,
    ]) {
      if (value.trim().isEmpty) {
        throw ArgumentError('Metadata filter values must not be blank.');
      }
    }
  }

  final Set<String> tags;
  final Set<String> requiredTags;
  final Set<String> types;
  final Set<String> statuses;
  final Set<String> pathPrefixes;
  final String? titleContains;
  final String? descriptionContains;

  bool allows(Map<String, Object?> raw, String path) {
    final rawTags = raw['tags'];
    final documentTags = rawTags is List
        ? rawTags.whereType<String>().toSet()
        : <String>{};
    // OKF defines the absent lifecycle status as stable. Keep producer-defined
    // values intact rather than collapsing all custom values to `unknown`.
    final status = raw.containsKey('status') ? raw['status'] : 'stable';
    bool contains(Object? value, String? query) =>
        query == null ||
        (value is String && value.toLowerCase().contains(query.toLowerCase()));
    return (tags.isEmpty || tags.any(documentTags.contains)) &&
        requiredTags.every(documentTags.contains) &&
        (types.isEmpty || types.contains(raw['type'])) &&
        (statuses.isEmpty || statuses.contains(status)) &&
        (pathPrefixes.isEmpty ||
            pathPrefixes.any(OkfConceptId.fromDocumentPath(path).isWithin)) &&
        contains(raw['title'], titleContains) &&
        contains(raw['description'], descriptionContains);
  }
}

/// Explicit consumer policy, never written into an OKF document.
class KnowledgeSearchPolicy {
  KnowledgeSearchPolicy({
    this.currentOnly = false,
    this.metadataFilter,
    this.asOf,
    Set<OkfLifecycleStatus>? statuses,
    Set<String> conceptTypes = const {},
    Set<String> pathPrefixes = const {},
    this.expandRelationships = false,
    Map<String, String> governingSources = const {},
  }) : statuses = statuses == null ? null : Set.unmodifiable(statuses),
       conceptTypes = Set.unmodifiable(conceptTypes),
       pathPrefixes = Set.unmodifiable(pathPrefixes),
       governingSources = Map.unmodifiable(governingSources) {
    if (currentOnly && asOf == null) {
      throw ArgumentError('currentOnly requires an explicit asOf date.');
    }
    for (final start in governingSources.keys) {
      final visited = <String>{};
      String? path = start;
      while (path != null) {
        if (!visited.add(path)) {
          throw ArgumentError('Cyclic governing sources: $start');
        }
        path = governingSources[path];
      }
    }
  }

  /// Additional frontmatter restrictions, combined with the policy below.
  final KnowledgeMetadataFilter? metadataFilter;

  /// Excludes deprecated/stale concepts, while retaining drafts and unverified
  /// material. Use [statuses] for an explicitly historical or narrower query.
  final bool currentOnly;
  final DateTime? asOf;
  final Set<OkfLifecycleStatus>? statuses;
  final Set<String> conceptTypes;
  final Set<String> pathPrefixes;
  final bool expandRelationships;

  /// Lower-authority concept path -> governing concept path. No inference from
  /// concept type, link label, verification tier, or similarity establishes it.
  final Map<String, String> governingSources;

  bool allows(KnowledgeSnapshot snapshot, String path) {
    final metadata = snapshot.metadataFor(path);
    return (metadataFilter?.allows(metadata.raw, path) ?? true) &&
        (!currentOnly ||
            (metadata.status != OkfLifecycleStatus.deprecated &&
                !metadata.isStale(asOf))) &&
        (statuses?.contains(metadata.status) ?? true) &&
        (conceptTypes.isEmpty || conceptTypes.contains(metadata.type)) &&
        (pathPrefixes.isEmpty ||
            pathPrefixes.any(OkfConceptId.fromDocumentPath(path).isWithin));
  }
}

/// A cited passage selected as a match, governing source, or related context.
class KnowledgeContextHit {
  const KnowledgeContextHit(
    this.result,
    this.reason, {
    this.viaPath,
    this.edge,
    this.fieldEdge,
  });
  final SearchResult result;
  final String reason;
  final String? viaPath;

  /// The okf graph edge a `relationship` hit was reached through, or
  /// [fieldEdge] when a frontmatter link field declared it.
  final OkfGraphEdge? edge;
  final OkfFieldEdge? fieldEdge;
}

/// What a [KnowledgeNotice] reports. [wireValue] is the stable code a host
/// matches; a later release may add codes, so a `switch` over them keeps a
/// default.
enum KnowledgeNoticeCode {
  /// A match links, through a typed `relationships` entry or a body link, to
  /// a target that resolves to no concept of the bundle.
  unresolvedRelationship('unresolved-relationship'),

  /// A match's `resource`, `sources[].resource`, `computation`,
  /// `executor.resource` or `attester.resource` is a path that names no file
  /// or directory, in the bundle or, for one that leaves the bundle, on
  /// disk. These fields cite what a concept rests on; they are not
  /// relationships.
  unresolvedSource('unresolved-source'),

  /// A governing source the search policy names is excluded by the policy or
  /// has no passage, so it could not be added as context.
  governingSourceUnavailable('governing-source-unavailable'),

  /// Another operation was refreshing the index, and the search served the
  /// last published generation (`StaleIndexPolicy.serveWhileRefreshing`).
  refreshInProgress('refresh-in-progress'),

  /// Files changed after the served generation was built, so passages cited
  /// from them may no longer match the files.
  sourceChanged('source-changed');

  const KnowledgeNoticeCode(this.wireValue);

  /// The kebab-case code, such as `unresolved-relationship`.
  final String wireValue;
}

/// Something a search reports besides its passages: a stable [code], the
/// sentence [message], and the [paths] it concerns.
///
/// A host tells notices apart by [code], never by their text. [text] is what
/// `wayfinder search` prints after `Notice: ` and lists under `notices` in its
/// JSON.
final class KnowledgeNotice {
  KnowledgeNotice(
    this.code,
    this.message, {
    Iterable<String> paths = const [],
    this.target,
    this.bundle,
  }) : paths = List.unmodifiable(paths);

  final KnowledgeNoticeCode code;

  /// The sentence for a reader, without the code or the name of the bundle
  /// it concerns, such as `An index refresh is running; these results come
  /// from the last completed index.`
  final String message;

  /// Bundle-relative paths it concerns, sorted:
  ///
  /// - [KnowledgeNoticeCode.unresolvedRelationship]: the matched concepts
  ///   whose link to [target] did not resolve;
  /// - [KnowledgeNoticeCode.unresolvedSource]: the matched concepts whose
  ///   source path [target] names nothing;
  /// - [KnowledgeNoticeCode.governingSourceUnavailable]: the governing
  ///   source;
  /// - [KnowledgeNoticeCode.sourceChanged]: every file added, removed or
  ///   edited since the served generation was built, while [message] names
  ///   at most ten;
  /// - [KnowledgeNoticeCode.refreshInProgress]: none.
  final List<String> paths;

  /// The link target or source path as written, for
  /// [KnowledgeNoticeCode.unresolvedRelationship] and
  /// [KnowledgeNoticeCode.unresolvedSource]; otherwise null.
  final String? target;

  /// The bundle it concerns, in the notices of a project search, which ranks
  /// several bundles together; null in one bundle's own response.
  final ProjectBundle? bundle;

  /// The line `wayfinder search` prints after `Notice: ` and lists under
  /// `notices` in its JSON: [message], after its code and a colon for
  /// `refresh-in-progress` and `source-changed`, as the command has always
  /// printed them, and after the [bundle]'s name and a colon when it has one.
  String get text {
    final line = switch (code) {
      KnowledgeNoticeCode.refreshInProgress ||
      KnowledgeNoticeCode.sourceChanged => '${code.wireValue}: $message',
      KnowledgeNoticeCode.unresolvedRelationship ||
      KnowledgeNoticeCode.unresolvedSource ||
      KnowledgeNoticeCode.governingSourceUnavailable => message,
    };
    return switch (bundle) {
      final bundle? => '${bundle.name}: $line',
      null => line,
    };
  }

  /// This notice, about [bundle].
  KnowledgeNotice about(ProjectBundle bundle) => KnowledgeNotice(
    code,
    message,
    paths: paths,
    target: target,
    bundle: bundle,
  );

  @override
  String toString() => text;
}

/// What a search collects for one notice sentence before it reports it.
typedef _NoticeFacts = ({
  KnowledgeNoticeCode code,
  String? target,
  Set<String> paths,
});

class KnowledgeSearchResponse {
  KnowledgeSearchResponse({
    required List<SearchResult> matches,
    required List<KnowledgeContextHit> context,
    required List<KnowledgeNotice> notices,
  }) : matches = List.unmodifiable(matches),
       context = List.unmodifiable(context),
       notices = List.unmodifiable(notices);

  /// Query-ranked matches, one best passage per concept.
  final List<SearchResult> matches;

  /// Bounded context after applying explicit governing and relationship policy.
  final List<KnowledgeContextHit> context;

  /// Missing/excluded governing context and unresolved links, one notice per
  /// sentence, in the order first found.
  final List<KnowledgeNotice> notices;
}

/// Synchronizes one bundle and searches an explicit eligible concept set.
///
/// The caller owns the store and embedder. Synchronization must not
/// overlap searches on this instance. Separate instances should coordinate
/// writes to the same bundle. Dense scoring is exact after eligibility filtering;
/// ObjectBox supplies indexed vector reads rather than a post-filtered ANN pool.
class KnowledgeIndex {
  /// Opens the snapshot and store from the same completed index generation.
  ///
  /// The caller verifies snapshot/configuration identity and owns the store and
  /// embedder. No synchronization, token fitting or document encoding occurs.
  /// Semantic search checks that every eligible passage has a compatible vector.
  KnowledgeIndex.fromSnapshot({
    required KnowledgeSnapshot snapshot,
    required this.store,
    required this.embedder,
    this.includeContext = false,
    this.bundleRoot,
  }) : countTokens = null,
       maxTokens = null,
       _snapshot = snapshot;

  KnowledgeIndex({
    required this.store,
    required this.embedder,
    this.includeContext = false,
    this.countTokens,
    this.maxTokens,
    this.bundleRoot,
  }) {
    if ((countTokens == null) != (maxTokens == null) ||
        (maxTokens != null && maxTokens! <= 0)) {
      throw ArgumentError(
        'Supply a tokenizer and positive maxTokens together.',
      );
    }
  }
  final BaseStore store;
  final BaseEmbedder embedder;
  final bool includeContext;
  final Future<int> Function(String)? countTokens;
  final int? maxTokens;

  /// The bundle's directory on disk, where a source path that leaves the
  /// bundle, such as `../../lib/billing.dart`, is looked up. Without it such
  /// a path is never reported as [KnowledgeNoticeCode.unresolvedSource]:
  /// the snapshot alone cannot tell whether it exists.
  final String? bundleRoot;
  KnowledgeSnapshot? _snapshot;
  bool _synchronizing = false;
  int _searches = 0;
  final _queryCache = <String, List<double>>{};

  String get embeddingModelName =>
      '${embedder.modelName}:okf-${includeContext ? 'context-v2' : 'body-v1'}';

  /// Embeds missing/changed inputs before one atomic replacement. Failed loads
  /// or inference leave the prior store/index usable. Other bundles are retained.
  ///
  /// [onEmbedded] reports the inputs embedded so far and the total, before
  /// the first batch of 32 and after each one. [cancel] is checked before
  /// each batch and before the store is written; a cancelled call throws
  /// `WayfinderException.cancelled()` and leaves the store as it was.
  Future<({int embeddedChunks, int removedChunks, int writtenChunks})>
  synchronize(
    KnowledgeSnapshot input, {
    void Function(int embedded, int total)? onEmbedded,
    WayfinderCancellation? cancel,
  }) async {
    if (_synchronizing || _searches > 0) {
      throw StateError(
        'Await active searches/synchronization before updating.',
      );
    }
    if (_snapshot != null && _snapshot!.bundleId != input.bundleId) {
      throw ArgumentError('Create a separate index for a different bundle ID.');
    }
    _synchronizing = true;
    try {
      final snapshot = countTokens == null
          ? input
          : await input.fitInputs(
              countTokens: countTokens!,
              maxTokens: maxTokens!,
              includeContext: includeContext,
            );
      final previous = {
        for (final chunk in await store.getAllChunks()) chunk.id: chunk,
      };
      final ids = snapshot.chunks.map((chunk) => chunk.id).toSet();
      final removed = previous.values
          .where(
            (chunk) =>
                (chunk.metadata['okf'] as Map?)?['bundleId'] ==
                    snapshot.bundleId &&
                !ids.contains(chunk.id),
          )
          .map((chunk) => chunk.id)
          .toSet();
      final model = embeddingModelName;
      final cached = (await store.getEmbeddingsForChunks(
        ids,
        source: embedder.sourceName,
        modelName: model,
      )).map((item) => item.chunkId).toSet();
      final pending = <({Chunk chunk, String text})>[];
      final writes = <Chunk>[];
      for (final chunk in snapshot.chunks) {
        final inputHashes = <String, Object?>{
          ...?previous[chunk.id]?.metadata['okfEmbeddingInputs']
              as Map<String, Object?>?,
        };
        final text = snapshot.textFor(chunk, includeContext: includeContext);
        final hash = sha256.convert(utf8.encode(text)).toString();
        if (!cached.contains(chunk.id) || inputHashes[model] != hash) {
          pending.add((chunk: chunk, text: text));
        }
        inputHashes[model] = hash;
        final updated = chunk.copyWith(
          metadata: {...chunk.metadata, 'okfEmbeddingInputs': inputHashes},
        );
        if (previous[chunk.id] != updated) writes.add(updated);
      }
      final vectors = <Embedding>[];
      onEmbedded?.call(0, pending.length);
      for (var offset = 0; offset < pending.length; offset += 32) {
        throwIfCancelled(cancel);
        final batch = pending.skip(offset).take(32).toList();
        final encoded = await embedder.generateEmbeddings(
          batch.map((item) => item.text).toList(),
        );
        if (encoded.length != batch.length ||
            encoded.any((vector) => vector.length != embedder.dimension)) {
          throw StateError('Embedder returned an invalid batch shape.');
        }
        for (var i = 0; i < batch.length; i++) {
          vectors.add(
            Embedding(
              chunkId: batch[i].chunk.id,
              source: embedder.sourceName,
              modelName: model,
              vector: encoded[i],
            ),
          );
        }
        onEmbedded?.call(offset + batch.length, pending.length);
      }
      throwIfCancelled(cancel);
      if (writes.isNotEmpty || vectors.isNotEmpty || removed.isNotEmpty) {
        await store.replaceChunks(
          chunks: writes,
          embeddings: vectors,
          removeChunkIds: removed,
        );
      }
      _snapshot = snapshot;
      return (
        embeddedChunks: pending.length,
        removedChunks: removed.length,
        writtenChunks: writes.length,
      );
    } finally {
      _synchronizing = false;
    }
  }

  /// Ranks the eligible passages by their similarity to [query] and adds the
  /// [policy]'s context.
  ///
  /// [cancel] is checked before the query is encoded and again before the
  /// passages are scored; a cancelled call throws
  /// `WayfinderException.cancelled()`. A query vector being encoded is not
  /// interrupted.
  Future<KnowledgeSearchResponse> search(
    String query, {
    KnowledgeSearchPolicy? policy,
    int limit = 5,
    int? contextLimit,
    WayfinderCancellation? cancel,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null || _synchronizing) {
      throw StateError('Synchronize the index before searching.');
    }
    throwIfCancelled(cancel);
    final budget = contextLimit ?? limit;
    if (query.trim().isEmpty || limit <= 0 || budget <= 0) {
      return KnowledgeSearchResponse(matches: [], context: [], notices: []);
    }
    final effective = policy ?? KnowledgeSearchPolicy();
    final eligible = _eligibleChunks(snapshot, effective);
    _searches++;
    try {
      final dense = <SearchResult>[];
      if (eligible.isNotEmpty) {
        final stored = await store.getEmbeddingsForChunks(
          eligible.keys.toSet(),
          source: embedder.sourceName,
          modelName: embeddingModelName,
        );
        if (stored.length != eligible.length) {
          throw StateError(
            'Dense search requires compatible embeddings for every eligible '
            'passage. Synchronize the index again.',
          );
        }
        final key = query.trim();
        final vector =
            _queryCache.remove(key) ?? await embedder.generateQueryVector(key);
        _queryCache[key] = vector;
        if (_queryCache.length > 100) {
          _queryCache.remove(_queryCache.keys.first);
        }
        throwIfCancelled(cancel);
        for (final embedding in stored) {
          dense.add(
            SearchResult(
              chunk: eligible[embedding.chunkId]!,
              embedding: embedding,
              similarity: cosineSimilarity(vector, embedding.vector),
            ),
          );
        }
        dense.sort((a, b) {
          final score = b.similarity.compareTo(a.similarity);
          if (score != 0) return score;
          final path = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
          return path == 0 ? a.chunk.id.compareTo(b.chunk.id) : path;
        });
      }
      return _contextForEligible(
        snapshot,
        eligible,
        dense,
        policy: effective,
        limit: limit,
        budget: budget,
      );
    } finally {
      _searches--;
    }
  }

  /// Applies the same eligibility and context policy to externally ranked hits.
  /// Unknown or excluded chunk IDs are ignored. Scores do not establish authority.
  KnowledgeSearchResponse contextForMatches(
    Iterable<SearchResult> ranked, {
    KnowledgeSearchPolicy? policy,
    int limit = 5,
    int? contextLimit,
  }) {
    final snapshot = _snapshot;
    if (snapshot == null || _synchronizing) {
      throw StateError('Synchronize the index before assembling context.');
    }
    final budget = contextLimit ?? limit;
    if (limit <= 0 || budget <= 0) {
      return KnowledgeSearchResponse(matches: [], context: [], notices: []);
    }
    final effective = policy ?? KnowledgeSearchPolicy();
    return _contextForEligible(
      snapshot,
      _eligibleChunks(snapshot, effective),
      ranked,
      policy: effective,
      limit: limit,
      budget: budget,
    );
  }

  Map<String, Chunk> _eligibleChunks(
    KnowledgeSnapshot snapshot,
    KnowledgeSearchPolicy policy,
  ) {
    final paths = snapshot.conceptPaths;
    for (final path in [
      ...policy.governingSources.keys,
      ...policy.governingSources.values,
    ]) {
      if (!paths.contains(path)) {
        throw ArgumentError('Unknown governing concept: $path');
      }
    }
    return {
      for (final chunk in snapshot.chunks)
        if (policy.allows(snapshot, chunk.sourcePath)) chunk.id: chunk,
    };
  }

  KnowledgeSearchResponse _contextForEligible(
    KnowledgeSnapshot snapshot,
    Map<String, Chunk> eligible,
    Iterable<SearchResult> ranked, {
    required KnowledgeSearchPolicy policy,
    required int limit,
    required int budget,
  }) {
    final best = <String, SearchResult>{};
    for (final hit in ranked) {
      if (eligible[hit.chunk.id] case final chunk?) {
        best.putIfAbsent(
          chunk.sourcePath,
          () => SearchResult(
            chunk: chunk,
            embedding: hit.embedding,
            similarity: hit.similarity,
          ),
        );
      }
    }
    final matches = best.values.take(limit).toList();
    final byPath = <String, Chunk>{};
    for (final chunk in eligible.values) {
      byPath.putIfAbsent(chunk.sourcePath, () => chunk);
    }
    final context = <KnowledgeContextHit>[];
    final seen = <String>{};
    // One notice per sentence, in the order first found, with every path
    // that led to it.
    final notices = <String, _NoticeFacts>{};
    void notice(
      KnowledgeNoticeCode code,
      String message, {
      required String path,
      String? target,
    }) => notices
        .putIfAbsent(
          message,
          () => (code: code, target: target, paths: <String>{}),
        )
        .paths
        .add(path);
    void add(
      String path,
      String reason, {
      String? via,
      OkfGraphEdge? edge,
      OkfFieldEdge? fieldEdge,
    }) {
      if (context.length >= budget || seen.contains(path)) return;
      final governor = policy.governingSources[path];
      if (governor != null) {
        if (!byPath.containsKey(governor)) {
          notice(
            KnowledgeNoticeCode.governingSourceUnavailable,
            'Governing source excluded or has no passage: $governor',
            path: governor,
          );
        } else {
          add(governor, 'governing', via: path);
        }
      }
      if (context.length >= budget || !seen.add(path)) return;
      final chunk = byPath[path];
      if (chunk == null) return;
      context.add(
        KnowledgeContextHit(
          best[path] ??
              SearchResult(chunk: chunk, embedding: null, similarity: 0),
          reason,
          viaPath: via,
          edge: edge,
          fieldEdge: fieldEdge,
        ),
      );
    }

    void follow(
      String source, {
      required OkfConceptId? targetConcept,
      required OkfGraphResolution resolution,
      required String rawTarget,
      OkfGraphEdge? edge,
      OkfFieldEdge? fieldEdge,
    }) {
      final target = targetConcept?.documentPath;
      if (target != null && byPath.containsKey(target)) {
        add(
          target,
          'relationship',
          via: source,
          edge: edge,
          fieldEdge: fieldEdge,
        );
      } else if (resolution == OkfGraphResolution.unresolved ||
          resolution == OkfGraphResolution.invalid) {
        notice(
          KnowledgeNoticeCode.unresolvedRelationship,
          'Unresolved relationship: $rawTarget',
          path: source,
          target: rawTarget,
        );
      }
    }

    for (final match in matches) {
      final source = match.chunk.sourcePath;
      add(source, 'match');
      if (!policy.expandRelationships) continue;
      for (final edge in snapshot.fieldEdges.where(
        (edge) => edge.source.documentPath == source,
      )) {
        follow(
          source,
          targetConcept: edge.targetConcept,
          resolution: edge.resolution,
          rawTarget: edge.rawTarget,
          fieldEdge: edge,
        );
      }
      for (final edge in snapshot.graph.edges.where(
        (edge) => edge.source.documentPath == source,
      )) {
        if (edge.origin == OkfGraphEdgeOrigin.bodyLink) {
          follow(
            source,
            targetConcept: edge.targetConcept,
            resolution: edge.resolution,
            rawTarget: edge.rawTarget,
            edge: edge,
          );
          continue;
        }
        // A path-valued field cites a source. One that names a concept is
        // still context; one that names nothing is a source problem.
        final target = edge.targetConcept?.documentPath;
        if (target != null && byPath.containsKey(target)) {
          add(target, 'relationship', via: source, edge: edge);
        } else if (_sourceMissing(snapshot, edge)) {
          notice(
            KnowledgeNoticeCode.unresolvedSource,
            'Unresolved source: ${edge.rawTarget}',
            path: source,
            target: edge.rawTarget,
          );
        }
      }
    }
    return KnowledgeSearchResponse(
      matches: matches,
      context: context,
      notices: [
        for (final MapEntry(key: message, :value) in notices.entries)
          KnowledgeNotice(
            value.code,
            message,
            paths: value.paths.toList()..sort(),
            target: value.target,
          ),
      ],
    );
  }

  /// Whether the path-valued [edge] names no file or directory, as the
  /// `path-targets-exist` builtin decides. okf's graph is bundle-scoped: a
  /// path that climbs out of the bundle is `invalid` to it, and one that
  /// starts with `/`, `./` or `../` but has whitespace is a `descriptor`,
  /// so those are looked up under [bundleRoot]. Bundle-root paths cannot
  /// climb above that root. An `invalid` path that stays in
  /// the bundle is malformed, and validation reports it, so it is not a
  /// missing source. URLs and prose descriptors name no path.
  bool _sourceMissing(KnowledgeSnapshot snapshot, OkfGraphEdge edge) {
    final target = _pathPart(edge.rawTarget);
    return switch (edge.resolution) {
      OkfGraphResolution.unresolved => !_targetExists(snapshot, edge, target),
      OkfGraphResolution.invalid =>
        _leavesBundle(edge, target) && !_targetExists(snapshot, edge, target),
      OkfGraphResolution.descriptor =>
        target != null &&
            (target.startsWith('/') ||
                target.startsWith('./') ||
                target.startsWith('../')) &&
            !_targetExists(snapshot, edge, target),
      OkfGraphResolution.resolvedConcept ||
      OkfGraphResolution.resolvedAsset ||
      OkfGraphResolution.external => false,
    };
  }

  /// As `path-targets-exist` decides: a target that starts with `/` stays in
  /// the bundle, and any other leaves when joining it to the source's
  /// directory climbs out.
  bool _leavesBundle(OkfGraphEdge edge, String? target) {
    if (target == null || target.startsWith('/')) return false;
    final joined = p.posix.normalize(
      p.posix.join(p.posix.dirname(edge.source.documentPath), target),
    );
    return joined == '..' || joined.startsWith('../');
  }

  /// Whether [target] names a file or directory the snapshot holds, or, when
  /// it leaves the bundle, one on disk under [bundleRoot]. Without a root a
  /// path that needs the disk counts as present, so it is not reported.
  bool _targetExists(
    KnowledgeSnapshot snapshot,
    OkfGraphEdge edge,
    String? target,
  ) {
    if (target == null || target.contains(r'\')) return false;
    final directory = target.startsWith('/')
        ? '.'
        : p.posix.dirname(edge.source.documentPath);
    final segments = <String>[];
    for (final segment in target.split('/')) {
      final decoded = _decodeSegment(segment);
      if (decoded.contains('/') || decoded.contains(r'\')) {
        return false;
      }
      segments.add(decoded);
    }
    final relative = p.posix.normalize(
      p.posix.joinAll([...directory.split('/'), ...segments]),
    );
    final inBundle = relative != '..' && !relative.startsWith('../');
    if (inBundle && _snapshotContains(snapshot, relative)) return true;
    if (!inBundle && target.startsWith('/')) return false;
    final root = bundleRoot;
    if (root == null) return !inBundle;
    return FileSystemEntity.typeSync(
          p.normalize(p.joinAll([root, ...directory.split('/'), ...segments])),
        ) !=
        FileSystemEntityType.notFound;
  }

  static bool _snapshotContains(KnowledgeSnapshot snapshot, String relative) {
    if (relative == '.') {
      return snapshot.sources.isNotEmpty || snapshot.assets.isNotEmpty;
    }
    if (snapshot.sources.containsKey(relative) ||
        snapshot.assets.contains(relative)) {
      return true;
    }
    final prefix = '$relative/';
    return snapshot.sources.keys.any((path) => path.startsWith(prefix)) ||
        snapshot.assets.any((path) => path.startsWith(prefix));
  }

  static String? _pathPart(String raw) {
    final cut = raw.indexOf(RegExp(r'[?#]'));
    final path = cut < 0 ? raw : raw.substring(0, cut);
    return path.isEmpty ? null : path;
  }

  static String _decodeSegment(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } on ArgumentError {
      return segment;
    } on FormatException {
      return segment;
    }
  }
}
