# Fixtures

## corpus/

`corpus/` is the local retrieval corpus. It mixes Dart, TypeScript, Markdown,
and plain text to exercise the default chunkers. The chunk golden test and the
BM25 regression gate both target this folder.

The corpus also holds the retrieval benchmark artifacts:

- `retrieval_queries.json` - query ids mapped to human-readable query text.
- `retrieval_qrels.json` - BEIR-style qrels ("query relevance judgments") keyed
  by the fixture-relative `stableId` emitted in comparison artifacts, with
  graded relevance from 0 to 3.
- `retrieval_query_groups.json` - query ids grouped by driver surface
  (`dart`, `typescript`, `markdown`) so comparison metrics can report
  per-language/document slices before changing defaults. The package fixture
  gate enforces minimum coverage for these slices so aggregate metrics cannot
  hide a missing TypeScript or Markdown driver.
- `bm25_metrics_baseline.json` - the checked-in exact BM25 baseline used by the
  package test-suite regression gate.
- `nomic_dense_hybrid_metrics_baseline.json` - optional local-model benchmark
  evidence for exact BM25, dense `nomic-embed-text`, and hybrid RRF captured
  against the 65-query grouped fixture. It is not used by CI because it requires
  a local Ollama daemon and model.
- `embeddinggemma_dimension_metrics_baseline.json` - optional local-model
  benchmark evidence for native 768-dim `embeddinggemma`, 512/256 MRL
  truncation, and their hybrid RRF variants, captured against the 65-query
  grouped fixture. It is not used by CI because it requires a local Ollama
  daemon and model.
- `qwen3_dimension_metrics_baseline.json` - optional local-model benchmark
  evidence for native 1024-dim `qwen3-embedding:0.6b`, 768/512/256 MRL
  truncation, and their hybrid RRF variants, captured against the 65-query
  grouped fixture. It is not used by CI because it requires a local Ollama
  daemon and model.

Keep new files that must not be chunked outside `corpus/`. The golden test
chunks every `.dart`, `.ts`, `.tsx`, `.md`, `.markdown`, and `.txt` file it
finds under the corpus root.
