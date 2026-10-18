import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:okf/okf.dart';
import 'package:wayfinder/wayfinder.dart' show OkfFieldEdge;

import '../../wayfinder_embeddings.dart';
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
    this.maxPassagesPerConcept = 1,
    this.maxRelationshipPassages,
    Map<String, String> governingSources = const {},
  }) : statuses = statuses == null ? null : Set.unmodifiable(statuses),
       conceptTypes = Set.unmodifiable(conceptTypes),
       pathPrefixes = Set.unmodifiable(pathPrefixes),
       governingSources = Map.unmodifiable(governingSources) {
    if (maxPassagesPerConcept < 1 ||
        (maxRelationshipPassages != null && maxRelationshipPassages! < 0)) {
      throw ArgumentError(
        'Passage limits must be positive (relationships may be zero).',
      );
    }
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

  /// Maximum query-ranked passages retained from one concept. Defaults to the
  /// historical one-passage policy; citations remain the original chunk ranges.
  final int maxPassagesPerConcept;

  /// When set, reserve at most this many slots for related concepts, after
  /// direct matches. Unused slots return to direct matches. At least one direct
  /// slot is retained. Null preserves historical match-then-links ordering.
  /// Explicit governing sources still precede the passages they govern.
  final int? maxRelationshipPassages;

  /// Lower-authority concept path -> governing concept path. No inference from
  /// concept type, link label, verification tier, or similarity establishes it.
  final Map<String, String> governingSources;

  bool allows(KnowledgeSnapshot snapshot, String path) {
    final metadata = snapshot.metadataFor(path);
    return (metadataFilter?.allows(metadata.raw, path) ?? true) &&
        (!currentOnly ||
            (metadata.status != OkfLifecycleStatus.deprecated &&
                !metadata.isStale(asOf))) &&
        (statuses == null || statuses!.contains(metadata.status)) &&
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

class KnowledgeSearchResponse {
  KnowledgeSearchResponse({
    required List<SearchResult> matches,
    required List<KnowledgeContextHit> context,
    required List<String> notices,
    Map<String, String> sourceTexts = const {},
    Map<String, String> governingSources = const {},
  }) : matches = List.unmodifiable(matches),
       context = List.unmodifiable(context),
       notices = List.unmodifiable(notices),
       sourceTexts = Map.unmodifiable(sourceTexts),
       governingSources = Map.unmodifiable(governingSources);

  /// Query-ranked matches, bounded by the selected per-concept passage policy.
  final List<SearchResult> matches;

  /// Bounded context after applying explicit governing and relationship policy.
  final List<KnowledgeContextHit> context;

  /// Missing/excluded governing context and unresolved links are visible here.
  final List<String> notices;

  /// Indexed source text for optional post-retrieval context assembly. This
  /// in-process data is not part of the CLI/MCP JSON representation.
  final Map<String, String> sourceTexts;

  /// Explicit dependencies retained for budget-safe context assembly.
  final Map<String, String> governingSources;
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
  }) : countTokens = null,
       maxTokens = null,
       _snapshot = snapshot;

  KnowledgeIndex({
    required this.store,
    required this.embedder,
    this.includeContext = false,
    this.countTokens,
    this.maxTokens,
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
  KnowledgeSnapshot? _snapshot;
  bool _synchronizing = false;
  int _searches = 0;
  final _queryCache = <String, List<double>>{};

  String get embeddingModelName =>
      '${embedder.modelName}:okf-${includeContext ? 'context-v2' : 'body-v1'}';

  /// Embeds missing/changed inputs before one atomic replacement. Failed loads
  /// or inference leave the prior store/index usable. Other bundles are retained.
  Future<({int embeddedChunks, int removedChunks, int writtenChunks})>
  synchronize(KnowledgeSnapshot input) async {
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
          metadata: {
            ...chunk.metadata,
            if (inputHashes.isNotEmpty) 'okfEmbeddingInputs': inputHashes,
          },
        );
        if (previous[chunk.id] != updated) writes.add(updated);
      }
      final vectors = <Embedding>[];
      for (var offset = 0; offset < pending.length; offset += 32) {
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
      }
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

  Future<KnowledgeSearchResponse> search(
    String query, {
    KnowledgeSearchPolicy? policy,
    int limit = 5,
    int? contextLimit,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null || _synchronizing) {
      throw StateError('Synchronize the index before searching.');
    }
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
    final effective = policy;
    final best = <String, SearchResult>{};
    final selected = <SearchResult>[];
    final selectedIds = <String>{};
    final selectedCounts = <String, int>{};
    for (final hit in ranked) {
      final chunk = eligible[hit.chunk.id];
      if (chunk == null || !selectedIds.add(chunk.id)) continue;
      final canonical = SearchResult(
        chunk: chunk,
        embedding: hit.embedding,
        similarity: hit.similarity,
      );
      best.putIfAbsent(chunk.sourcePath, () => canonical);
      final count = selectedCounts[chunk.sourcePath] ?? 0;
      if (count < effective.maxPassagesPerConcept) {
        selected.add(canonical);
        selectedCounts[chunk.sourcePath] = count + 1;
      }
    }
    final matches = selected.take(limit).toList();
    final byPath = <String, Chunk>{};
    for (final chunk in eligible.values) {
      byPath.putIfAbsent(chunk.sourcePath, () => chunk);
    }
    final context = <KnowledgeContextHit>[];
    final seen = <String>{};
    final contextCounts = <String, int>{};
    var relationshipCount = 0;
    final notices = <String>[];
    void add(
      String path,
      String reason, {
      String? via,
      SearchResult? direct,
      OkfGraphEdge? edge,
      OkfFieldEdge? fieldEdge,
    }) {
      final count = contextCounts[path] ?? 0;
      if (context.length >= budget ||
          count >= effective.maxPassagesPerConcept ||
          (direct == null && count > 0)) {
        return;
      }
      if (reason == 'relationship' &&
          effective.maxRelationshipPassages != null &&
          relationshipCount >= effective.maxRelationshipPassages!) {
        return;
      }
      final governor = effective.governingSources[path];
      if (governor != null) {
        if (!byPath.containsKey(governor)) {
          notices.add('Governing source excluded or has no passage: $governor');
        } else {
          add(governor, 'governing', via: path);
        }
      }
      final chunk = direct?.chunk ?? best[path]?.chunk ?? byPath[path];
      if (chunk == null || context.length >= budget || !seen.add(chunk.id)) {
        return;
      }
      contextCounts[path] = count + 1;
      if (reason == 'relationship') relationshipCount++;
      context.add(
        KnowledgeContextHit(
          direct ??
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
        notices.add('Unresolved relationship: $rawTarget');
      }
    }

    void expand(String source) {
      if (!effective.expandRelationships) return;
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
        follow(
          source,
          targetConcept: edge.targetConcept,
          resolution: edge.resolution,
          rawTarget: edge.rawTarget,
          edge: edge,
        );
      }
    }

    final relationshipLimit = effective.maxRelationshipPassages;
    if (relationshipLimit == null) {
      for (final match in matches) {
        add(match.chunk.sourcePath, 'match', direct: match);
        expand(match.chunk.sourcePath);
      }
    } else {
      final reserved = effective.expandRelationships
          ? relationshipLimit.clamp(0, budget - 1)
          : 0;
      final directCount = budget - reserved;
      for (final match in matches.take(directCount)) {
        add(match.chunk.sourcePath, 'match', direct: match);
      }
      for (final source in matches.map((hit) => hit.chunk.sourcePath).toSet()) {
        expand(source);
      }
      for (final match in matches.skip(directCount)) {
        add(match.chunk.sourcePath, 'match', direct: match);
      }
    }
    return KnowledgeSearchResponse(
      matches: matches,
      context: context,
      notices: notices.toSet().toList(),
      sourceTexts: {
        for (final path in {
          ...matches.map((hit) => hit.chunk.sourcePath),
          ...context.map((hit) => hit.result.chunk.sourcePath),
        })
          path: snapshot.sources[path]!,
      },
      governingSources: effective.governingSources,
    );
  }
}
