import 'package:meta/meta.dart';

import 'candidate_expansion.dart';
import 'parent_child_resolver.dart';
import 'search_options.dart';
import 'searcher.dart';

/// Wraps a precise child [Searcher] and returns expanded parent context.
///
/// This keeps retrieval and presentation separate: the wrapped searcher still
/// ranks the most precise chunks, while the resolver maps those hits to larger
/// file/class/namespace context for callers that need more code around a match.
@immutable
class ParentChildSearcher {
  /// Creates a parent-child searcher around [searcher].
  const ParentChildSearcher({
    required Searcher searcher,
    required ParentChildResolver resolver,
    this.deduplicateContexts = true,
  }) : _searcher = searcher,
       _resolver = resolver;

  final Searcher _searcher;
  final ParentChildResolver _resolver;

  /// Whether repeated context chunks should collapse to the first child hit.
  final bool deduplicateContexts;

  /// Searches precise chunks, then expands each hit to parent context.
  ///
  /// Results keep the wrapped searcher's ordering. When [deduplicateContexts]
  /// is true, only the first child hit for each context chunk is returned.
  Future<List<ParentChildSearchResult>> search(
    String query, {
    int limit = 5,
    SearchOptions? options,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || limit <= 0) {
      return const [];
    }

    return fetchUntilFiltered<ParentChildSearchResult>(
      limit: limit,
      fetch: (fetchLimit) => _searcher.search(
        normalizedQuery,
        limit: fetchLimit,
        options: options,
      ),
      refine: (candidates) => _resolver.expand(
        candidates,
        deduplicateContexts: deduplicateContexts,
      ),
    );
  }
}
