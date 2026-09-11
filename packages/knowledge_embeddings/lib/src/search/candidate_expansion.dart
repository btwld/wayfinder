import '../models/search_result.dart';

/// Default ceiling on how far the fetch limit may grow, as a multiple of the
/// caller's limit.
const int defaultMaxExpansionFactor = 32;

/// Fetches candidates with a doubling limit until [refine] yields [limit] items.
///
/// [fetch] asks the underlying source for a number of candidates. [refine] maps
/// those candidates to the values the caller wants, dropping the ones it
/// rejects. The loop stops when [refine] produces enough values, when [fetch]
/// returns fewer candidates than asked (the source is exhausted), or when the
/// fetch limit reaches `limit * maxExpansionFactor`.
Future<List<T>> fetchUntilFiltered<T>({
  required int limit,
  required Future<List<SearchResult>> Function(int fetchLimit) fetch,
  required List<T> Function(List<SearchResult> candidates) refine,
  int maxExpansionFactor = defaultMaxExpansionFactor,
}) async {
  var fetchLimit = limit;
  final maxFetchLimit = limit * maxExpansionFactor;

  while (true) {
    final candidates = await fetch(fetchLimit);
    final refined = refine(candidates);

    if (refined.length >= limit) {
      return refined.take(limit).toList();
    }

    // The source returned fewer than requested, so no more candidates exist.
    if (candidates.length < fetchLimit || fetchLimit >= maxFetchLimit) {
      return refined;
    }

    fetchLimit = (fetchLimit * 2).clamp(1, maxFetchLimit);
  }
}
