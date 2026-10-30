# ADR-0017: Use dense-only retrieval

- Status: accepted
- Date: 2026-10-18
- Scope: retrieval APIs, CLI/MCP and evaluation tooling; no OKF or Profile rule
- Supersedes: retrieval defaults in [0009](0009-local-knowledge-retrieval.md) and mode exposure in [0010](0010-wayfinder-cli.md)
- Driver: maintainer direction to simplify retrieval support

## Context and decision

Overlapping lexical, BM25, dense and hybrid paths expanded APIs, fixtures and
command contracts. Use dense retrieval for every actual library, CLI, MCP and
evaluator search. This is a maintenance/product choice, not evidence that dense
retrieval is universally superior.

Require an embedder for `KnowledgeIndex`, including saved snapshots. Remove
retrieval modes, lexical/hybrid/RRF APIs and CLI/MCP `mode` inputs without aliases
or fallback; reject retired arguments with migration guidance. Search requires a
compatible saved index and usable model and never implicitly indexes.

Retain generic search/reranking, TEI, parent/child expansion, model/vector identity,
storage, lifecycle policy, citations, context windows and opt-in grouping. Model
failures stay errors. The OKF adapter refuses an eligible passage without a
compatible vector; generic ingestion callers still own partial-coverage checks.
Valid empty queries/corpora or excluded scopes can return no results.

## Consequences

This breaks Dart and command APIs: supply `embedder:`, remove retired symbols and
arguments, replace hybrid search with `ContentSearcher`, and refresh MCP discovery.
See [migration](../../packages/wayfinder_embeddings/README.md#dense-only-migration).
The cutoff changes no model identity or snapshot format, so compatible indexes
remain usable and bundles need no migration.

Preview, snapshot parsing and structural goldens stay model-free; actual relevance
evaluation uses a real model. Historical scores retain their original corpus,
policy and runtime attribution; extracting a dense row is not a rerun.
Reconsider another method only for a concrete need and reviewed evidence within
an explicit maintenance, relevance, latency and storage budget.
