import '../models/search_result.dart';
import 'search_options.dart';

/// One ranked-retrieval entry point.
///
/// `ContentSearcher`, `HybridContentSearcher`, and `RerankingContentSearcher`
/// implement it, so composition needs no delegate typedefs.
abstract interface class Searcher {
  /// Returns at most [limit] results for [query], best first.
  ///
  /// [options] filters candidates before they are ranked.
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    SearchOptions? options,
  });
}
