# 1.0.0 (unreleased)

- Prepare the first stable standalone Dart chunker, with public compatibility
  and support boundaries in [the stability contract](../../docs/stability.md).
- Include fields declared by enhanced enums, with their source lines and enum
  scope, as class fields already are. Re-ingest affected Dart files to include
  those previously omitted declarations. The existing judged-corpus chunks
  are unchanged.
- `DartChunker` moves here from `wayfinder_embeddings` 0.2.0, so
  `wayfinder_embeddings` no longer depends on `analyzer`. Apart from the
  enhanced-enum fields above, its chunks, ids and metadata are unchanged.
- `defaultCodeRegistry()` registers `DartChunker` beside the TypeScript,
  Markdown and text chunkers of `wayfinder_embeddings`, with optional
  per-chunker budgets.
- Supports `analyzer` `>=8.4.1 <11.0.0`.
