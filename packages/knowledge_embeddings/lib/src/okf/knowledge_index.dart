import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:okf/okf.dart';

import '../../knowledge_embeddings.dart';
import '../util/similarity.dart';
import 'knowledge_snapshot.dart';

enum KnowledgeRetrievalMode { bm25, dense, hybrid }

/// Explicit consumer policy, never written into an OKF document.
class KnowledgeSearchPolicy {
  KnowledgeSearchPolicy({
    this.currentOnly = false,
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
    return (!currentOnly ||
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
  });
  final SearchResult result;
  final String reason;
  final String? viaPath;
  final OkfGraphEdge? edge;
}

class KnowledgeSearchResponse {
  KnowledgeSearchResponse({
    required List<SearchResult> matches,
    required List<KnowledgeContextHit> context,
    required List<String> notices,
  }) : matches = List.unmodifiable(matches),
       context = List.unmodifiable(context),
       notices = List.unmodifiable(notices);

  /// Query-ranked matches, one best passage per concept.
  final List<SearchResult> matches;

  /// Bounded context after applying explicit governing and relationship policy.
  final List<KnowledgeContextHit> context;

  /// Missing/excluded governing context and unresolved links are visible here.
  final List<String> notices;
}

/// Synchronizes one bundle and searches an explicit eligible concept set.
///
/// The caller owns the store and optional embedder. Synchronization must not
/// overlap searches on this instance. Separate instances should coordinate
/// writes to the same bundle. Dense scoring is exact after eligibility filtering;
/// ObjectBox supplies indexed vector reads rather than a post-filtered ANN pool.
class KnowledgeIndex {
  /// Opens the snapshot and store from the same completed index generation.
  ///
  /// The caller verifies snapshot/configuration identity and owns the store and
  /// embedder. No synchronization, token fitting or document encoding occurs.
  /// Semantic search checks that every eligible passage has a compatible vector.
  factory KnowledgeIndex.openSnapshot({
    required KnowledgeSnapshot snapshot,
    required BaseStore store,
    BaseEmbedder? embedder,
    bool includeContext = false,
  }) => KnowledgeIndex(
    store: store,
    embedder: embedder,
    includeContext: includeContext,
  ).._snapshot = snapshot;

  KnowledgeIndex({
    required this.store,
    this.embedder,
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
  final BaseEmbedder? embedder;
  final bool includeContext;
  final Future<int> Function(String)? countTokens;
  final int? maxTokens;
  KnowledgeSnapshot? _snapshot;
  BM25LexicalIndex? _lexical;
  bool _synchronizing = false;
  int _searches = 0;
  final _queryCache = <String, List<double>>{};

  String? get embeddingModelName => embedder == null
      ? null
      : '${embedder!.modelName}:okf-${includeContext ? 'context' : 'body'}-v1';

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
      final cached = embedder == null
          ? <String>{}
          : (await store.getEmbeddingsForChunks(
              ids,
              source: embedder!.sourceName,
              modelName: model!,
            )).map((item) => item.chunkId).toSet();
      final pending = <({Chunk chunk, String text})>[];
      final writes = <Chunk>[];
      for (final chunk in snapshot.chunks) {
        final inputHashes = <String, Object?>{
          ...?previous[chunk.id]?.metadata['okfEmbeddingInputs']
              as Map<String, Object?>?,
        };
        if (embedder != null) {
          final text = snapshot.textFor(chunk, includeContext: includeContext);
          final hash = sha256.convert(utf8.encode(text)).toString();
          if (!cached.contains(chunk.id) || inputHashes[model] != hash) {
            pending.add((chunk: chunk, text: text));
          }
          inputHashes[model!] = hash;
        }
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
        final encoded = await embedder!.generateEmbeddings(
          batch.map((item) => item.text).toList(),
        );
        if (encoded.length != batch.length ||
            encoded.any((vector) => vector.length != embedder!.dimension)) {
          throw StateError('Embedder returned an invalid batch shape.');
        }
        for (var i = 0; i < batch.length; i++) {
          vectors.add(
            Embedding(
              chunkId: batch[i].chunk.id,
              source: embedder!.sourceName,
              modelName: model!,
              vector: encoded[i],
            ),
          );
        }
      }
      // Construct the new read snapshot before committing the store update.
      final lexical = BM25LexicalIndex.fromChunks(
        snapshot.chunks.map(
          (chunk) => chunk.copyWith(
            id: chunk.id,
            content: snapshot.textFor(chunk, includeContext: includeContext),
          ),
        ),
      );
      if (writes.isNotEmpty || vectors.isNotEmpty || removed.isNotEmpty) {
        await store.replaceChunks(
          chunks: writes,
          embeddings: vectors,
          removeChunkIds: removed,
        );
      }
      _snapshot = snapshot;
      _lexical = lexical;
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
    KnowledgeRetrievalMode mode = KnowledgeRetrievalMode.bm25,
    KnowledgeSearchPolicy? policy,
    int limit = 5,
    int? contextLimit,
    int candidateLimit = 50,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null || _synchronizing) {
      throw StateError('Synchronize the index before searching.');
    }
    if (candidateLimit <= 0) {
      throw ArgumentError.value(candidateLimit, 'candidateLimit');
    }
    final budget = contextLimit ?? limit;
    if (query.trim().isEmpty || limit <= 0 || budget <= 0) {
      return KnowledgeSearchResponse(matches: [], context: [], notices: []);
    }
    final effective = policy ?? KnowledgeSearchPolicy();
    final conceptPaths = snapshot.conceptPaths;
    for (final path in [
      ...effective.governingSources.keys,
      ...effective.governingSources.values,
    ]) {
      if (!conceptPaths.contains(path)) {
        throw ArgumentError('Unknown governing concept: $path');
      }
    }
    _searches++;
    try {
      final eligible = {
        for (final chunk in snapshot.chunks)
          if (effective.allows(snapshot, chunk.sourcePath)) chunk.id: chunk,
      };
      final options = SearchOptions(
        filePaths: eligible.values
            .map((chunk) => chunk.sourcePath)
            .toSet()
            .toList(),
      );
      final lexical = mode == KnowledgeRetrievalMode.dense || eligible.isEmpty
          ? <SearchResult>[]
          : (_lexical ??= BM25LexicalIndex.fromChunks(
                  snapshot.chunks.map(
                    (chunk) => chunk.copyWith(
                      id: chunk.id,
                      content: snapshot.textFor(
                        chunk,
                        includeContext: includeContext,
                      ),
                    ),
                  ),
                ))
                .search(query, limit: snapshot.chunks.length, options: options)
                .where((hit) => eligible.containsKey(hit.chunk.id))
                .map(
                  (hit) => SearchResult(
                    chunk: eligible[hit.chunk.id]!,
                    embedding: null,
                    similarity: hit.similarity,
                  ),
                )
                .toList();
      final dense = <SearchResult>[];
      if (mode != KnowledgeRetrievalMode.bm25) {
        if (embedder == null) {
          throw StateError('Semantic search requires an embedder.');
        }
        if (eligible.isNotEmpty) {
          final key = query.trim();
          final vector =
              _queryCache.remove(key) ??
              await embedder!.generateQueryVector(key);
          _queryCache[key] = vector;
          if (_queryCache.length > 100) {
            _queryCache.remove(_queryCache.keys.first);
          }
          final stored = await store.getEmbeddingsForChunks(
            eligible.keys.toSet(),
            source: embedder!.sourceName,
            modelName: embeddingModelName!,
          );
          if (stored.length != eligible.length) {
            throw StateError('Vectors changed; synchronize the index again.');
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
      }
      final ranked = switch (mode) {
        KnowledgeRetrievalMode.bm25 => lexical,
        KnowledgeRetrievalMode.dense => dense,
        KnowledgeRetrievalMode.hybrid => ReciprocalRankFusion.fuse([
          lexical
              .take(candidateLimit < limit ? limit : candidateLimit)
              .toList(),
          dense.take(candidateLimit < limit ? limit : candidateLimit).toList(),
        ], limit: eligible.length),
      };
      return contextForMatches(
        ranked,
        policy: effective,
        limit: limit,
        contextLimit: budget,
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
    final paths = snapshot.conceptPaths;
    for (final path in [
      ...effective.governingSources.keys,
      ...effective.governingSources.values,
    ]) {
      if (!paths.contains(path)) {
        throw ArgumentError('Unknown governing concept: $path');
      }
    }
    final eligible = {
      for (final chunk in snapshot.chunks)
        if (effective.allows(snapshot, chunk.sourcePath)) chunk.id: chunk,
    };
    final best = <String, SearchResult>{};
    for (final hit in ranked.where(
      (hit) => eligible.containsKey(hit.chunk.id),
    )) {
      final chunk = eligible[hit.chunk.id]!;
      best.putIfAbsent(
        chunk.sourcePath,
        () => SearchResult(
          chunk: chunk,
          embedding: hit.embedding,
          similarity: hit.similarity,
        ),
      );
    }
    final matches = best.values.take(limit).toList();
    final byPath = <String, Chunk>{};
    for (final chunk in eligible.values) {
      byPath.putIfAbsent(chunk.sourcePath, () => chunk);
    }
    final context = <KnowledgeContextHit>[];
    final seen = <String>{};
    final notices = <String>[];
    void add(String path, String reason, {String? via, OkfGraphEdge? edge}) {
      if (context.length >= budget || seen.contains(path)) return;
      final governor = effective.governingSources[path];
      if (governor != null) {
        if (!byPath.containsKey(governor)) {
          notices.add('Governing source excluded or has no passage: $governor');
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
        ),
      );
    }

    for (final match in matches) {
      add(match.chunk.sourcePath, 'match');
      if (!effective.expandRelationships) continue;
      for (final edge in snapshot.graph.edges.where(
        (edge) => edge.source.documentPath == match.chunk.sourcePath,
      )) {
        final target = edge.targetConcept?.documentPath;
        if (target != null && byPath.containsKey(target)) {
          add(target, 'relationship', via: match.chunk.sourcePath, edge: edge);
        } else if (edge.resolution == OkfGraphResolution.unresolved ||
            edge.resolution == OkfGraphResolution.invalid) {
          notices.add('Unresolved relationship: ${edge.rawTarget}');
        }
      }
    }
    return KnowledgeSearchResponse(
      matches: matches,
      context: context,
      notices: notices.toSet().toList(),
    );
  }
}
