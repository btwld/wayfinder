---
type: Architecture Decision Record
title: Resolve path targets from the loaded inventory
description: One public resolver serves validation and retrieval, with inventory membership inside the bundle and disk lookup only outside it.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:23:07Z
sources:
  - id: decision-path-targets
    title: Inventory-authoritative path targets
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#inventory-authoritative-path-targets
---

# Decision

Use one public path resolver for validation and retrieval, with injected inventory membership and disk lookup only outside the bundle. Candidate deletions and malformed encoded paths previously depended on graph classification or stale files on disk; strict OKF segment decoding and the loaded inventory now determine internal targets. Missing or malformed citations can gain findings/notices, and literal percent signs must be encoded as `%25`.
