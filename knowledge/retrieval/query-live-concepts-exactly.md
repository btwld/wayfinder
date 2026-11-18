---
type: Architecture Decision Record
title: Query live concepts exactly
description: Read-only structured queries in the core project library, shared by CLI and MCP, with saved query ids in `.wayfinder/queries/`.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:26:03Z
sources:
  - id: decision-exact-queries
    title: Exact queries over live concepts
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#exact-queries-over-live-concepts
---

# Decision

Add read-only structured queries to the core project library and share their contract through CLI/MCP, so reusable metadata views need neither a per-project renderer script nor semantic ranking. Saved query IDs resolve versioned local JSON in the consuming project's `.wayfinder/queries/`; the existing metadata predicate remains available to embeddings consumers, and no OKF/Profile semantics change. Every query scans/fingerprints live sources and refuses partial data, paying filesystem cost without promising a transactional snapshot or computation attestation; see [queries](../../docs/queries.md).
