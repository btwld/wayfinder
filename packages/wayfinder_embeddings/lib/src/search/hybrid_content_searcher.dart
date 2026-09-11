import 'dart:math' as math;

import '../models/search_result.dart';
import '../util/checks.dart';
import 'bm25_lexical_index.dart';
import 'reciprocal_rank_fusion.dart';
import 'search_options.dart';
import 'searcher.dart';

/// Combines exact BM25 lexical search with dense/vector search using RRF.
class HybridContentSearcher implements Searcher {
  HybridContentSearcher({
    required BM25LexicalIndex lexicalIndex,
    required Searcher semanticSearcher,
    int candidateLimit = 50,
    int rrfRankConstant = ReciprocalRankFusion.defaultRankConstant,
  }) : _lexicalIndex = lexicalIndex,
       _semanticSearcher = semanticSearcher,
       _candidateLimit = checkPositive(candidateLimit, 'candidateLimit'),
       _rrfRankConstant = checkPositive(rrfRankConstant, 'rrfRankConstant');

  final BM25LexicalIndex _lexicalIndex;
  final Searcher _semanticSearcher;
  final int _candidateLimit;
  final int _rrfRankConstant;

  /// Searches lexical and semantic indexes, then fuses ranked lists with RRF.
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

    final lexicalResults = _lexicalIndex.search(
      normalizedQuery,
      limit: resolvedCandidateLimit,
      options: options,
    );
    final semanticResults = await _semanticSearcher.search(
      normalizedQuery,
      limit: resolvedCandidateLimit,
      options: options,
    );

    return ReciprocalRankFusion.fuse(
      [lexicalResults, semanticResults],
      limit: limit,
      rankConstant: _rrfRankConstant,
    );
  }
}
