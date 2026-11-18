---
type: Architecture Decision Record
title: Read Profile sources from the project's repository or a managed mirror
description: Committed objects of the project's own repository are borrowed without a mirror, and abandoned mirrors are collected under sibling locks.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:23:07Z
sources:
  - id: decision-mirror-collection
    title: Collect abandoned Profile mirrors
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#collect-abandoned-profile-mirrors
  - id: decision-borrowed-reads
    title: Borrow committed same-repository Profile objects
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#borrow-committed-same-repository-profile-objects
---

# Decision

## Collect abandoned Profile mirrors

Record successful mirror use and collect mirrors of missing local sources or sufficiently unused mirrors under sibling locks, because removed worktrees leave them behind (#181).
Legacy mirrors get an observation period, dry runs write nothing, and package snapshots survive; reinstalling skills after eviction may require a fetch.
Keep metadata outside mirrors for partial-deletion retries and require ownership evidence for staging cleanup, retaining lock files and unknown staging directories.

## Borrow committed same-repository Profile objects

Borrow committed Profile objects from the project's own repository to avoid
duplicate mirrors across self-hosting checkouts and worktrees (#181).
The cost is extra Git discovery and possible failure if external Git changes
remove objects during resolution; see
[source resolution](../../docs/wayfinder-configuration.md).
