# 0.1.0 (unreleased)

- Initial release. `DartChunker` moves here from `wayfinder_embeddings` 0.2.0
  unchanged, so `wayfinder_embeddings` no longer depends on `analyzer`. Its
  chunks, ids and metadata are those 0.2.0 produced.
- `defaultCodeRegistry()` registers `DartChunker` beside the TypeScript,
  Markdown and text chunkers of `wayfinder_embeddings`, with optional
  per-chunker budgets.
- Supports `analyzer` `>=8.4.1 <11.0.0`.
