---
type: Architecture Decision Record
title: Embed with a verified local model
description: Verified local Arctic Embed XS Q8_0 weights, chosen on size and cost.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:26:03Z
sources:
  - id: adr-0009
    title: "ADR-0009: Use Arctic Embed XS for local knowledge embeddings"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#local-embeddings-with-arctic-xs-adr-0009
---

# Decision

Use verified local Arctic Embed XS Q8_0 weights: in [synthetic comparisons](../../packages/wayfinder_embeddings/fixtures/README.md), XS matched larger Q8 models on 50 of 60 first-context judgments with lower per-query cost, supporting a size/cost choice rather than a general accuracy claim.
Local inference costs model download, startup and disk space; omitting footnote definitions beside ordinary body passages reduces citation competition but can miss useful support, so reviewed regressions or independent-corpus gains should trigger reconsideration.
Retrieval modes were replaced by [Use dense-only retrieval](retrieve-with-dense-search-only.md); model/input identity remains [pinned separately](../../packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart).
