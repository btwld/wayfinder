# 0.1.0 (unreleased)

- Include fields declared by enhanced enums, with their source lines and enum
  scope, as class fields already are. Re-ingest affected Dart files to include
  those previously omitted declarations. The existing judged-corpus chunks
  are unchanged.
- Initial release. `DartChunker` moves here from `wayfinder_embeddings` 0.2.0
  unchanged, so `wayfinder_embeddings` no longer depends on `analyzer`. Its
  chunks, ids and metadata are those 0.2.0 produced.
- `defaultCodeRegistry()` registers `DartChunker` beside the TypeScript,
  Markdown and text chunkers of `wayfinder_embeddings`, with optional
  per-chunker budgets.
- Supports `analyzer` `>=8.4.1 <11.0.0`.
