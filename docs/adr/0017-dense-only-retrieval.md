# ADR-0017: Use dense-only retrieval

- Status: accepted
- Date: 2026-10-18
- Scope: retrieval APIs, application command contracts, and developer tooling; no OKF or Profile rule changes
- Supersedes: only the retrieval defaults in [ADR-0009](0009-local-knowledge-retrieval.md) and mode exposure in [ADR-0010](0010-wayfinder-cli.md)
- Driver: maintainer direction to simplify retrieval support

## Context

The library, application, and evaluation tools exposed overlapping retrieval
paths, defaults, and model-free behaviors. Maintaining those choices expanded
APIs, fixtures, CLI/MCP contracts, and documentation. The maintainer selected
dense-only retrieval as a product simplification. This is not an experimental
finding that dense retrieval is universally superior.

Historical measurements remain evidence for their original model, corpus,
judgments, policy, and runtime. Removing a retrieval path does not invalidate
those observations or turn a filtered report into a new experiment.

## Decision

Use dense retrieval for every actual library, CLI, MCP, and evaluator search.
Require an embedder for `KnowledgeIndex`, including saved-snapshot construction.
Remove `KnowledgeRetrievalMode`, search `mode:`, and the OKF hybrid-only
`candidateLimit:`. Remove BM25, lexical tokenization, hybrid search, and
reciprocal-rank-fusion APIs without deprecated aliases or fallback paths.

Remove CLI `--mode` and MCP `mode`, including explicit dense values. Reject
retired inputs with migration guidance; do not reinterpret them as dense or
silently discard unsupported MCP fields. Actual search requires a current
compatible saved index and a usable local model. It does not implicitly index.

Retain generic `Searcher`, dense `ContentSearcher`, parent/child expansion,
rerankers, TEI, `rerank:dense`, and generic reranker candidate limits. Preserve
model identity, vector identity, storage, metadata eligibility, lifecycle policy,
source citations, relationship expansion, context windows, query caches, and
concurrency boundaries. Opt-in section/message grouping remains opt-in; this
cutoff changes neither its policy nor the paragraph/CLI defaults.

Chunk preview, golden validation, and snapshot parsing remain model-free, but
must not be described as actual retrieval evaluation. Normal evaluators load a
real model. Deterministic test vectors may check mechanisms, not supply a fake
relevance baseline. Structural fixture gates remain separate from genuine
native dense gates. The retained dense baseline is an explicitly attributed
extraction of the historical dense row, not a rerun.

The OKF adapter fails before ranking when an eligible passage lacks a compatible
vector. Generic `ContentSearcher` rejects a nonempty eligible collection with
no compatible embeddings on its empty-result path. It does not scan every
successful ANN query or guarantee partial coverage; generic ingestion callers
own that boundary. Valid empty queries, empty corpora, or fully excluded scopes
can still return empty results. Model-load failures remain errors with the
configured local model path, not empty success or another retrieval method.

## Consequences

This breaks Dart and command contracts. Consumers supply `embedder:`, remove
retired arguments and symbols, replace the hybrid searcher with `ContentSearcher`,
and refresh MCP discovery. Developer tools use `dense` or `rerank:dense`;
`llamadart` remains a dense alias. Evaluators no longer use `--native` as a
model-free toggle. See the [migration guide](../../packages/wayfinder_embeddings/README.md#dense-only-migration)
and [evaluation guide](../../packages/wayfinder_embeddings/README.md#evaluation).

The cutoff itself changes no model/input identity, saved snapshot format,
ObjectBox schema, or source projection. Compatible existing indexes remain
usable. Independent changes to input formats or chunking policies retain their
own rebuild requirements. No release is published by this decision, and no
bundle or Profile migration is required.

The accepted Arctic XS model choice and remaining ADR-0009 rationale stand.
ADR-0010's indexing lifecycle, direct-first context policy, persistent MCP
encoder, and source-window behavior stand. Retired multi-method reports are
linked through [immutable history](../../packages/wayfinder_embeddings/fixtures/README.md),
not maintained as active execution guidance.

## Reconsider when

A concrete consumer need and reviewed evidence justify another retrieval method
within an explicit maintenance, relevance, latency, and storage budget. Such a
change needs its own explicit contract and evaluation; it must not reappear as
an implicit fallback for an unavailable encoder.
