import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../models/search_result.dart';
import '../util/checks.dart';
import 'search_options.dart';
import 'search_reranker.dart';
import 'searcher.dart';

/// Wraps a first-pass [Searcher] with a cross-encoder reranking stage.
///
/// The wrapped searcher is asked for a wider candidate window, then the
/// [SearchReranker] scores those candidates against the query and returns the
/// requested top results.
@immutable
class RerankingContentSearcher implements Searcher {
  /// Creates a reranking searcher around a first-pass [searcher].
  RerankingContentSearcher({
    required Searcher searcher,
    required SearchReranker reranker,
    int candidateLimit = 50,
  }) : _searcher = searcher,
       _reranker = reranker,
       _candidateLimit = checkPositive(candidateLimit, 'candidateLimit');

  final Searcher _searcher;
  final SearchReranker _reranker;
  final int _candidateLimit;

  /// Searches for candidates, reranks them, and returns at most [limit] results.
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    int? candidateLimit,
    SearchOptions? options,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || limit <= 0) {
      return const [];
    }

    final resolvedCandidateLimit = math.max(
      limit,
      candidateLimit == null
          ? _candidateLimit
          : checkPositive(candidateLimit, 'candidateLimit'),
    );
    final candidates = await _searcher.search(
      normalizedQuery,
      limit: resolvedCandidateLimit,
      options: options,
    );
    return _reranker.rerank(
      query: normalizedQuery,
      candidates: candidates,
      limit: limit,
    );
  }
}
