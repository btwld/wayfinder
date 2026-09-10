# Changelog

## 0.0.1-dev.0

- Verifies the pinned ObjectBox release archive by SHA-256 before any of its
  bytes reach the package, replacing the upstream download script, with a
  pinned hash for every platform upstream publishes and no architecture
  fallback.
- Keys stored vectors on the model's bytes and preprocessing contract only, so
  another mirror of the same verified artifact reuses them.
- Retries a cold native backend start once, because the first load from a
  freshly installed bundle can exceed the runtime's worker startup timeout, and
  reports the retry count through `LlamaEmbedder.coldStartRetries`.
- Chunks Markdown footnote definitions as `footnote` apparatus and keeps them
  out of OKF passages, where attribution resolves through `sources`.
- Regenerates raw per-process benchmark reports instead of checking in
  multi-megabyte archives; summaries and provenance stay in `fixtures/`.
- Records the accepted local model/defaults and measured improvement priorities
  in ADR-0009, with available CLI commands and their current scope.
- Adds repeatable Arctic XS/S and BGE-small model comparisons, with pinned Q8/Q4
  experimental artifacts, per-model tokenizer validation, and isolated indexes.
- Adds isolated keyword/BM25/dense/hybrid benchmarks over 160 topic-separated
  questions, plus compiled startup/cache/update, build, and 1k–50k storage sweeps.
- Shares the lexical tokenizer and canonical context assembly with diagnostic
  rankers, preserving scope and original citation text for external rankings.

- Adds an upstream-OKF adapter with original citations, contextual token-budget
  splitting, explicit lifecycle/scope/governing/link policy, and atomic bundle
  synchronization that reuses unchanged vectors.
- Measures seven retrieval configurations over separate development and held-out
  fixture queries with BM25, local dense, and hybrid modes on both stores.

- Chunks Dart, TypeScript, Markdown, and text files into stable, addressable
  segments with line ranges and symbol metadata.
- Ranks chunks with exact BM25, local llamadart vectors, and Reciprocal Rank
  Fusion, with optional reranking and parent/child expansion.
- Stores chunks and embeddings in `MemoryStore` or the optional 384-dimension
  `ObjectBoxStore`.
- Ships a 65-query qrels fixture, a checked-in BM25 metrics baseline, and a
  regression gate test over `fixtures/corpus`.
- Keeps reusable example inputs in `fixtures/samples`, with full chunk goldens
  for both corpora and portable fixture paths and line endings.
- Deduplicates pending ingestion batches, releases benchmark resources after
  factory failures, and preserves Markdown code/table boundaries and headings.
- Computes stable cosine similarity for very large and very small finite vectors.
- Tokenizes each BM25 document once and removes redundant forwarding and copying
  in model, embedder, storage, and workflow paths.
- Pins a 25.28 MB Arctic Embed XS Q8_0 model; verifies size and SHA-256,
  separates query/document encoding, and rejects token overflow by default.
- Stages cached model downloads during preparation and bundles weights, native
  libraries, manifest, and model license with the retrieval CLI.
- Protects existing databases from incompatible vector-schema changes; reindex
  source files into a fresh directory.
- Exercises the selected store for lexical benchmarks as well as semantic runs.
- Preserves supplied Markdown metadata and refreshes metadata during ingestion
  without re-encoding unchanged content.
- Preserves ObjectBox entity IDs on updates, deletes chunks/vectors atomically,
  rejects invalid float32 vectors, and falls back to exact scoring within a
  model when ANN filtering leaves too few usable results.
- Adds 13 diagnostic knowledge cases for authority, lifecycle, freshness,
  paraphrases, negation, explicit scopes, and unanswerable questions.
- Initial package release; provides the retrieval implementation used by Station.
