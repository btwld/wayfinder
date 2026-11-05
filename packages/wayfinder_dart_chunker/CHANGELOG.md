# 1.0.0 (unreleased)

- Prepare the first stable standalone Dart chunker, with public compatibility
  and support boundaries in [the stability contract](../../docs/stability.md).
- Include fields declared by enhanced enums, with their source lines and enum
  scope, as class fields already are. Re-ingest affected Dart files to include
  those previously omitted declarations. The existing judged-corpus chunks
  are unchanged.
- Constructor chunks now cover named and unnamed class/enum constructors,
  factory/redirecting constructors and extension-type constructors, with
  consistent name, scope and return-type metadata, plus `const`, `external`
  and initializer metadata. Re-ingest affected Dart files; constructor chunks,
  IDs and metadata can change. Judged-corpus goldens were updated.
- `DartChunker` moves here from `wayfinder_embeddings` 0.2.0, so
  `wayfinder_embeddings` no longer depends on `analyzer`. Apart from the
  enhanced-enum fields and constructor corrections above, its chunks, ids and metadata are unchanged.
- `defaultCodeRegistry()` registers `DartChunker` beside the TypeScript,
  Markdown and text chunkers of `wayfinder_embeddings`, with optional
  per-chunker budgets.
- Supports `analyzer` `>=8.4.1 <11.0.0`.
