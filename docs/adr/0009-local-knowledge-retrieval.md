# ADR-0009: Keep Arctic XS for local knowledge embeddings

- Status: accepted
- Date: 2026-09-09
- Revised: 2026-09-29 (evidence audit after the 2026-09-28 condensation; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0009-local-knowledge-retrieval.md))
- Scope: retrieval tooling; no bundle or Profile rule changes

## Context

The [retrieval](../wayfinder_embeddings_comparison.md) and
[model](../wayfinder_embeddings_model_comparison.md) comparisons tested
keyword, BM25, dense and hybrid retrieval, then compared Arctic Embed XS Q8_0
with Arctic S Q8/Q4 and BGE-small Q8/Q4 on identical passages and frozen
judgments. On the 60 answerable test questions, XS and both larger Q8 models
returned the expected first context in 50 cases. XS had the highest measured
recall@10 among the candidates and lower new-query cost than the larger Q8
models; BGE-small Q4 was slightly smaller but lost one first-context judgment.
These are synthetic, previously inspected partitions, not independent
real-corpus evidence, and the benchmark's context-policy results are not
current CLI accuracy.

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

- **Footnote projection:** Keep the current projection as a **retrieval
  heuristic** for ordinary OKF passages. OKF §5.1 defines how a footnote label joins a
  `sources` entry; it does not require consumers to discard footnote prose.
  The current projection omits definitions when ordinary body content exists
  because one measured citation-only definition competed with its body. It
  preserves the original source text. Generic Markdown chunking retains typed
  footnote chunks for non-OKF consumers, and headings/footnotes remain
  searchable when they are the entire OKF body. This is an implementation
  tradeoff, not an OKF or Profile rule.

## Consequences

Existing vectors for the pinned model need no rebuild because of this
decision. Excluding definitions can miss prose found only there; reopen that
choice if reviewed queries demonstrate lost support. Preserve paired
regressions and storage/cache measurements when comparing models.

Passage selection, judgment quality, answerability, and large-index performance
remain evaluation questions, not bundle rules or reasons to infer confidence
from a ranked candidate. The benchmark uses an explicit governing-source map,
lifecycle policy, relationship expansion and ten context slots; the CLI uses a
different policy and limit. The linked reports own measurements and experiment
detail, and their scores must not be presented as current CLI accuracy.

## Evaluation questions

1. Compare one versus two or three passages per concept and bounded adjacent
   context under the same total token budget; report raw ranking separately
   from assembled context.
2. Review alternate supporting passages independently, preserve the historical
   fixture, and use fresh questions before tuning against corrected judgments.
3. If an answering consumer needs abstention, calibrate it on development data
   and report both unsupported returns and missed answerable questions. Do not
   use an arbitrary similarity threshold as confidence.
4. If storage scale warrants optimization, compare selective ANN or allocation
   changes with exact eligible-vector results, including filtering, updates,
   recall and latency.

These are hypotheses and evaluation safeguards, not required architecture or a
claim that all four must be completed before this provisional model choice can
be used.

## Reconsider when

Reopen the footnote heuristic when reviewed queries show that a definition is
the best available support, or when a controlled inclusion/exclusion comparison
shows that the precision tradeoff no longer holds. Reopen model selection when
an independently reviewed corpus shows a useful quality gain within an explicit
download, startup, latency, memory and storage budget, or when runtime
compatibility requires a replacement.
