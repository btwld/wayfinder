---
type: Decision
title: Define compatibility in the stability contract and release on main evidence
description: Public surfaces and obligations live in `docs/stability.md`, and a release needs successful CI from the exact commit's push to main plus hosted CLI resolution.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: decision-compatibility-evidence
    title: Prepared 0.5 compatibility and release evidence
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#prepared-05-compatibility-and-release-evidence
---

# Decision

Define the prepared public surfaces and compatibility obligations in the [0.5 contract](../../docs/stability.md), because embedders and machine consumers need an explicit boundary across independently versioned packages; public breaking changes carry breaking releases (the next 0.x minor) and migration notes, while Profile releases remain independent. The packages stay on 0.x, so the unpublished 1.0.0 became 0.5.0 with the same obligations.
Require successful source CI from the exact commit's push to main and independent hosted CLI resolution before release eligibility, because a green PR or workspace resolution cannot establish those facts; the [read-only preflight and remaining distribution gates](release-wayfinder.md#release-preflight) can therefore stay blocked on unpublished siblings or missing main evidence without declaring failed candidate code.
