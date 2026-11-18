---
type: Architecture Decision Record
title: Publish upstream findings unchanged
description: okf's report is published as okf wrote it, Profile results use its finding grammar, and engine health stays in separate diagnostics.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:23:07Z
sources:
  - id: adr-0008
    title: "ADR-0008: Publish okf's finding report unchanged"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#publish-upstream-findings-unchanged-adr-0008
---

# Decision

Publish okf's report unchanged and use its finding grammar for Profile results, keeping engine health in separate diagnostics, because translating findings would lose identifiers/severity semantics and create a second wire contract.
Advisories cannot become strict failures, and a Profile finding never enters the OKF report; consumers must read the separate components defined by the [result contract](../../implementation/okf-implementation-guide.md#41-results-and-exit-codes).
