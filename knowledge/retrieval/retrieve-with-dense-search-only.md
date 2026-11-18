---
type: Architecture Decision Record
title: Retrieve with dense search only
description: Library, CLI, MCP and evaluation searches are dense, with no lexical or hybrid mode and no implicit fallback.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:26:03Z
sources:
  - id: adr-0017
    title: "ADR-0017: Use dense-only retrieval"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#dense-only-retrieval-adr-0017
---

# Decision

Use dense retrieval throughout actual library, CLI/MCP and evaluation searches, removing lexical/hybrid modes and implicit fallback to reduce maintained APIs, fixtures and command contracts; this is a product/maintenance choice, not proof that dense is universally better.
Consumers must supply an embedder and migrate retired arguments, while preview/parsing remain model-free, compatible snapshots remain usable and model failures stay errors.
The [migration/evaluation guide](../../packages/wayfinder_embeddings/README.md#dense-only-migration) retains generic reranking/context policy and historical evidence attribution; another method needs a concrete need and reviewed quality/cost evidence.
