# 0.1.0-beta.1 (unreleased)

- Add `SqliteGenerationFormat` for immutable saved indexes and exact filtered
  search through sqlite-vec v0.1.9.
- Add `DriftStore` for mutable chunk and embedding storage. `findSimilar` is
  an exact full scan of one source and model, scored with sqlite-vec's cosine
  distance function, not a KNN index.
- Report a missing embedding chunk as `ArgumentError` and roll back the batch.
