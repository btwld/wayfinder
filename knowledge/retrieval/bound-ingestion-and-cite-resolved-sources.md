---
type: Architecture Decision Record
title: Bound ingestion and cite resolved sources
description: Search Markdown shows the shared resolver's source decisions, encoder failure is attributed at its own calls, and ingestion is bounded by digests and a temporary spool.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:26:03Z
sources:
  - id: decision-retrieval-sources
    title: Retrieval source decisions and bounded ingestion
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#retrieval-source-decisions-and-bounded-ingestion
---

# Decision

Carry the [shared resolver](../validation/resolve-path-targets-from-the-inventory.md)'s source decisions from the snapshot into search Markdown so displayed paths agree with `unresolved-source` notices. Attribute encoder failure at its own calls, including a returned vector with the wrong dimension or a non-finite component, and decode freshness through the loader's UTF-8 rules, preserving healthy models when bundle I/O fails; ingestion uses digest validation and a temporary spool to bound retained text, while keeping store-batch atomicity rather than promising call-wide rollback.
