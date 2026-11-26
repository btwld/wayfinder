# 0.1.0-beta.1 (unreleased)

- Move `ObjectBoxStore` and its native setup from `wayfinder_embeddings`.
  Existing databases retain their schema and open from the same directory.
- Index vectors with 64 neighbors per node and an indexing search count of
  100, and raise the default `minimumSearchCandidates` from 50 to 200.
  `findSimilar` now returns the exact top 10 for all 260 queries over 2,675
  real-model passages, up from 88% of those results, at about 7 ms per query
  instead of 2 ms. Existing databases open as before; ObjectBox rebuilds their
  vector index once.
