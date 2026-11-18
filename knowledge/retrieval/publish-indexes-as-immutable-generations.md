---
type: Architecture Decision Record
title: Publish indexes as immutable plain-file generations
description: Snapshot and vector generations with an atomically replaced pointer, readable during refresh, plus the model lookup order.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:26:03Z
sources:
  - id: adr-0022
    title: "ADR-0022: Keep indexes as plain-file generations"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#immutable-plain-file-index-generations-adr-0022-adr-0026
  - id: adr-0026
    title: "ADR-0026: Find a host's model, and match source paths to the builtin"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#immutable-plain-file-index-generations-adr-0022-adr-0026
---

# Decision

Replace application ObjectBox indexes with immutable snapshot/vector generations and an atomically replaced current pointer so readers can use the previous publication during refresh without a writer lock; the old HNSW index was unused, so exhaustive scoring preserves ranking behavior.
Search exposes refresh/source-change notices and refuses stale snapshots outside refresh, while every index/prune collects expired generations; duplicate storage during staging, rebuilds on upgrade, deferred Windows deletion and filesystem-dependent locking remain costs.
[Storage and source notices](../../packages/wayfinder_cli/README.md#local-storage) remain operational docs, and [model lookup](../../packages/wayfinder_cli/README.md#embedding-model-lookup) uses explicit override, installed bundle, working/source development models, then verified cache, correcting the former order.
