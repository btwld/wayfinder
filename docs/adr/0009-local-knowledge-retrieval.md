# ADR-0009: Use Arctic Embed XS for local knowledge embeddings

- Status: accepted
- Date: 2026-09-09
- Scope: retrieval tooling; no bundle or Profile rule

## Context

Benchmarks over the fixtures in
[`packages/wayfinder_embeddings/fixtures/`](../../packages/wayfinder_embeddings/fixtures/README.md)
compared keyword, BM25, dense, and hybrid retrieval, then compared Arctic
Embed XS Q8_0 with Arctic S Q8/Q4 and BGE-small Q8/Q4 on identical passages
and frozen judgments. On the 60 answerable test questions, XS and both larger
Q8 models returned the expected first context in 50 cases. XS had the highest
recall@10 of the candidates and a lower per-query cost than the larger Q8
models; BGE-small Q4 was slightly smaller but lost one first-context
judgment. These are synthetic partitions, not independent real-corpus
evidence, and their scores are not current CLI accuracy.

## Decision

Use Arctic Embed XS Q8_0 as the verified local model, with artifact and
preprocessing identity pinned by
[`localEmbeddingModel`](../../packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart).
Inference uses local weights; preparation handles download and verification.
Changing a download mirror without changing the verified bytes does not
invalidate vector identity.

The reusable OKF adapter defaults to BM25; dense and hybrid retrieval stay
optional. The Wayfinder application makes its own fixed semantic-search
choice in [ADR-0010](0010-wayfinder-cli.md). Similarity never establishes
authority, freshness, correctness, or answerability. ObjectBox is optional
storage, not a relevance policy.

Passage projection omits footnote definitions when a concept has ordinary
body content, because a citation-only definition competed with its own body
in measured queries. It keeps the source text, and headings and footnotes stay
searchable when they are a concept's entire body. This is a retrieval
heuristic, not an OKF or Profile rule.

## Consequences

Excluding footnote definitions can miss prose found only there. Model
comparisons must keep paired regressions and storage and cache measurements.
Passage selection, answerability, and large-index performance remain
evaluation questions, never reasons to infer confidence from a ranked
candidate.

## Reconsider when

Reviewed queries show a footnote definition is the best available support, or
an independently reviewed corpus shows a useful quality gain within an
explicit download, startup, latency, memory, and storage budget, or runtime
compatibility requires a replacement.
