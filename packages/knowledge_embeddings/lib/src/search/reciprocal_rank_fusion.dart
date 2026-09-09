import '../models/search_result.dart';

/// Rank-based fusion for combining multiple retrieval result lists.
///
/// RRF avoids score normalization between retrieval methods by summing
/// `1 / (rankConstant + rank)` for each chunk across ranked lists.
class ReciprocalRankFusion {
  const ReciprocalRankFusion._();

  /// Standard RRF rank constant used by common hybrid search systems.
  static const int defaultRankConstant = 60;

  /// Fuses [rankedLists] into a single ranked result list.
  static List<SearchResult> fuse(
    Iterable<List<SearchResult>> rankedLists, {
    int limit = 5,
    int rankConstant = defaultRankConstant,
  }) {
    if (rankConstant <= 0) {
      throw ArgumentError.value(
        rankConstant,
        'rankConstant',
        'must be greater than zero',
      );
    }
    if (limit <= 0) {
      return const [];
    }

    final candidates = <String, _FusedCandidate>{};
    var firstSeen = 0;

    for (final rankedList in rankedLists) {
      final seenInList = <String>{};
      for (var index = 0; index < rankedList.length; index++) {
        final result = rankedList[index];
        final chunkId = result.chunk.id;
        if (!seenInList.add(chunkId)) {
          continue;
        }

        final rank = index + 1;
        final score = 1 / (rankConstant + rank);
        final candidate = candidates[chunkId];
        if (candidate == null) {
          candidates[chunkId] = _FusedCandidate(
            result: result,
            score: score,
            bestRank: rank,
            firstSeen: firstSeen++,
          );
        } else {
          candidate.score += score;
          if (rank < candidate.bestRank) {
            candidate.bestRank = rank;
          }
          if (candidate.result.embedding == null && result.embedding != null) {
            candidate.result = result;
          }
        }
      }
    }

    final fused = candidates.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byBestRank = a.bestRank.compareTo(b.bestRank);
        if (byBestRank != 0) return byBestRank;
        return a.firstSeen.compareTo(b.firstSeen);
      });

    return fused
        .take(limit)
        .map((candidate) {
          return SearchResult(
            chunk: candidate.result.chunk,
            embedding: candidate.result.embedding,
            similarity: candidate.score,
          );
        })
        .toList(growable: false);
  }
}

class _FusedCandidate {
  _FusedCandidate({
    required this.result,
    required this.score,
    required this.bestRank,
    required this.firstSeen,
  });

  SearchResult result;
  double score;
  int bestRank;
  final int firstSeen;
}
