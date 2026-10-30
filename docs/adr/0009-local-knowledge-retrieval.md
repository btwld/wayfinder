# ADR-0009: Use Arctic Embed XS for local knowledge embeddings

- Status: accepted; retrieval defaults superseded by [ADR-0017](0017-dense-only-retrieval.md)
- Date: 2026-09-09
- Scope: retrieval tooling; no bundle or Profile rule

## Context and decision

Use Arctic Embed XS Q8_0 for verified local embeddings, with artifact and
preprocessing identity pinned by
[`localEmbeddingModel`](../../packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart).
The [synthetic fixtures](../../packages/wayfinder_embeddings/fixtures/README.md)
compared XS with Arctic S Q8/Q4 and BGE-small Q8/Q4 on identical passages and
frozen judgments. XS and both larger Q8 models found the expected first context
on 50 of 60 answerable questions; XS had the highest recall@10 and lower
per-query cost than the larger Q8 models. BGE-small Q4 was slightly smaller
but lost one first-context judgment. This supports a local size/cost choice,
not a claim about current CLI accuracy or independent real corpora.

Inference uses local weights; preparation downloads and verifies them. A mirror
change preserving verified bytes does not change vector identity. The original
BM25/dense/hybrid defaults are historical; ADR-0017 selects dense-only search.
ObjectBox was storage, not relevance policy; [ADR-0022](0022-plain-file-index-generations.md)
replaces it with plain files.

## Consequences

Similarity establishes neither authority nor answerability. Passage projection
omits footnote definitions beside ordinary body content to avoid competing with
its own citations; source text is retained, and footnote-only bodies remain
searchable. This heuristic can miss supporting prose found only in a definition.

Reconsider on reviewed footnote regressions, runtime incompatibility, or an
independent corpus showing a useful gain within explicit download, startup,
latency, memory and storage budgets. Keep paired regressions in comparisons.
