# ADR-0009: Keep Arctic XS for optional local embeddings

- Status: accepted
- Date: 2026-09-09
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0009-local-knowledge-retrieval.md))
- Scope: retrieval tooling; no bundle or Profile rule changes

## Context

The [retrieval](../wayfinder_embeddings_comparison.md) and
[model](../wayfinder_embeddings_model_comparison.md) comparisons found no
reviewed quality gain that justified replacing Arctic Embed XS Q8_0 with a
larger or quantized candidate. XS had lower measured query cost and artifact
size. The synthetic questions had been inspected, so those results are
bounded evidence, not a general quality claim.

## Decision

Keep Arctic Embed XS Q8_0 as the verified local model, with artifact and
preprocessing identity pinned by
[`localEmbeddingModel`](../../packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart).
Runtime inference uses local weights; preparation handles download and
verification. Changing a download mirror without changing verified bytes
does not invalidate vector identity.

The reusable OKF adapter defaults to BM25; dense and hybrid retrieval remain
optional. The Wayfinder application makes its own fixed semantic-search choice
in [ADR-0010](0010-wayfinder-cli.md). Similarity never establishes authority,
freshness, correctness, or answerability. ObjectBox remains optional storage,
not a relevance policy.

Exclude footnote definitions from ordinary OKF passages: OKF resolves
per-claim attribution through `sources`, and short definition lines otherwise
compete with the body they cite. A body containing only headings and
footnotes remains searchable. Generic Markdown chunking still retains
footnotes for non-OKF consumers.

## Options considered

- Replacing XS with a larger or quantized model was rejected because the
  reviewed comparison did not show a gain within the measured resource budget.

## Consequences

Existing vectors for the pinned model need no rebuild because of this
decision. Excluding definitions can miss prose found only there; reopen that
choice if reviewed queries demonstrate lost support. Preserve paired
regressions and storage/cache measurements when comparing models.

Passage selection, answerability, and large-index performance remain
evaluation questions, not bundle rules or reasons to infer confidence from a
ranked candidate. The linked reports own measurements and experiment detail.

## Reconsider when

Reopen model selection when an independently reviewed corpus shows a useful
quality gain within an explicit download, startup, latency, memory, and storage
budget, or when runtime compatibility requires a replacement.
