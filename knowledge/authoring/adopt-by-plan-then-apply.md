---
type: Architecture Decision Record
title: Adopt by plan, then apply
description: A previewable plan and a guarded apply, offline relock, and adoption requests that refuse parent and `.git` segments.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: adr-0020
    title: "ADR-0020: Programmatic adoption as plan, then apply"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#adoption-as-plan-then-apply-adr-0020-adr-0024-adr-0025
  - id: adr-0024
    title: "ADR-0024: Pin the generator revision, and relock offline"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#adoption-as-plan-then-apply-adr-0020-adr-0024-adr-0025
  - id: adr-0025
    title: "ADR-0025: Give a host the adoption seams it runs"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#adoption-as-plan-then-apply-adr-0020-adr-0024-adr-0025
  - id: decision-adoption-paths
    title: Bounded adoption paths and process cleanup
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#bounded-adoption-paths-and-process-cleanup
---

# Decision

## Adoption as plan then apply

Provide a previewable plan then guarded apply for hosts, approving each fetched source, binding the package's declared id, digesting host inputs and sharing the assessor; offline relock reuses pinned commits without Git or skill writes.
Planning may populate the external cache, but applying refuses stale/conflicting inputs and holds the project lock across owned writes/undo; failed steps roll back where possible, host writes require host-managed cleanup, and final validation runs after unlock without undoing applied files.
Adoption therefore can remain incomplete after a failed final gate, and existing bindings remain migration work; [adoption API/seeds](../../packages/wayfinder/README.md#adoption) keep agent configuration and invented concepts outside the library's ownership.

## Bounded adoption paths and process cleanup

Refuse parent segments and any-case `.git` segments at the adoption request boundary, for the bundle, host inputs and seed concepts, before preparing writes, because normalized aliases hid unsafe intent. Freeze Git's root through termination and discover descendants until the frozen tree stops growing within one inspection budget. A failed listing kills those verified descendants with the root and resumes only non-root ids whose parentage no longer matches. POSIX PID operations remain best effort because they are not atomic process handles.
