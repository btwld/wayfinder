# 0.1.0-beta.1 (unreleased)

- Move `ObjectBoxStore` and its native setup from `wayfinder_embeddings`.
  Existing databases retain their schema and open from the same directory.
- Index vectors with 64 neighbors per node and an indexing search count of
  100, and raise the default `minimumSearchCandidates` from 50 to 200, so
  `findSimilar` results match exact ranking far more closely at about three
  times the query cost. Existing databases open as before; ObjectBox rebuilds
  their vector index once.
