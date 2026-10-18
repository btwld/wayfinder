import 'dart:collection';

import '../embedding/base_embedder.dart';
import '../models/search_result.dart';
import '../storage/base_store.dart';
import '../util/checks.dart';
import 'candidate_expansion.dart';
import 'search_options.dart';
import 'searcher.dart';

/// A class for searching content using embeddings.
///
/// This class combines an embedder and a store to provide semantic search
/// functionality for content.
class ContentSearcher implements Searcher {
  /// The store containing the chunks and embeddings.
  final BaseStore _store;

  /// The embedder used to generate query embeddings.
  final BaseEmbedder _embedder;

  /// Lightweight LRU cache for query vectors to prevent redundant computation.
  final LinkedHashMap<String, List<double>> _queryCache =
      LinkedHashMap<String, List<double>>();
  final int _maxCacheSize;

  /// Creates a new content searcher.
  ///
  /// [store] is the store containing the chunks and embeddings.
  /// [embedder] is the embedder used to generate query embeddings.
  /// [maxCacheSize] is the maximum number of query vectors to cache (defaults to 100).
  ContentSearcher({
    required BaseStore store,
    required BaseEmbedder embedder,
    int maxCacheSize = 100,
  }) : _store = store,
       _embedder = embedder,
       _maxCacheSize = checkNonNegative(maxCacheSize, 'maxCacheSize');

  /// Retrieves the query vector from cache, or generates and caches it.
  Future<List<double>> _getQueryVector(String query) async {
    final cached = _queryCache.remove(query);
    if (cached != null) {
      // Re-insert to mark as most recently used
      _queryCache[query] = cached;
      return cached;
    }

    final vector = await _embedder.generateQueryVector(query);

    if (_maxCacheSize <= 0) {
      return vector;
    }

    if (_queryCache.length >= _maxCacheSize) {
      // Remove least recently used (first element)
      _queryCache.remove(_queryCache.keys.first);
    }
    _queryCache[query] = vector;

    return vector;
  }

  /// Searches for content similar to the query.
  ///
  /// [query] is the natural language query.
  /// [limit] is the maximum number of results to return.
  /// [options] is an optional set of search options to filter the results.
  ///
  /// Returns a list of search results, sorted by similarity (highest first).
  ///
  /// A nonempty eligible collection without compatible vectors throws. The
  /// coverage check runs only when retrieval is empty; partial vector coverage
  /// remains the ingestion caller's responsibility. Use KnowledgeIndex for an
  /// exact per-passage coverage check before ranking an OKF snapshot.
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    SearchOptions? options,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || limit <= 0) {
      return const [];
    }

    final queryVector = await _getQueryVector(normalizedQuery);

    final List<SearchResult> results;
    if (options == null) {
      results = await _store.findSimilar(
        queryVector,
        _embedder.sourceName,
        _embedder.modelName,
        limit: limit,
      );
    } else {
      results = await fetchUntilFiltered<SearchResult>(
        limit: limit,
        fetch: (fetchLimit) => _store.findSimilar(
          queryVector,
          _embedder.sourceName,
          _embedder.modelName,
          limit: fetchLimit,
        ),
        refine: (candidates) => candidates
            .where((result) => options.matchesFilters(result.chunk))
            .toList(),
      );
    }
    if (results.isEmpty) {
      // Only the empty-result path inspects the eligible collection. Normal
      // ANN queries do not scan the corpus or promise complete vector coverage.
      final eligible = (await _store.getAllChunks())
          .where((chunk) => options?.matchesFilters(chunk) ?? true)
          .map((chunk) => chunk.id)
          .toSet();
      if (eligible.isNotEmpty &&
          (await _store.getEmbeddingsForChunks(
            eligible,
            source: _embedder.sourceName,
            modelName: _embedder.modelName,
          )).isEmpty) {
        throw StateError(
          'Dense search requires compatible embeddings for the eligible '
          'collection. Ingest it with the configured embedder before searching.',
        );
      }
    }
    return results;
  }
}
