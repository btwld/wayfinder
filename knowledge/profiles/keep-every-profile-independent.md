---
type: Architecture Decision Record
title: Keep every Profile independent
description: Every Profile is its own package with its own parent and executable rules, and every rule sees the vocabulary of the whole chain plus the project.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:23:07Z
sources:
  - id: adr-0016
    title: "ADR-0016: Every Profile is an independent package the validator enforces"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#independent-profile-packages-adr-0016
  - id: adr-0027
    title: "ADR-0027: Shared effective vocabulary"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#shared-effective-vocabulary-adr-0027
---

# Decision

## Independent Profile packages

Make every Profile an independent package with its own parent and executable conformance rules, because a second corpus needed no Bitwild base and prose authority had made “passes validation but fails the Profile” possible.
Authority is OKF → engine contract → package; README/skills explain judgment, `get` pins sources, and validation reads the local lock/cache, reporting unassessed execution as INCOMPLETE rather than silently passing rules.
This gives up consumer overrides and inherited-rule relaxation: changes need the package/engine release processes, and the flat lock cannot represent two revisions of one id; see [Profile packages](../../implementation/okf-implementation-guide.md#5-profile-packages).

## Shared effective vocabulary

Give every rule the vocabulary of the whole Profile chain plus the project, because the shipped child Profile extends tags accepted by inherited rules; children cannot replace, remove or re-grade inherited definitions, but their vocabulary can change inherited findings.
This keeps existing verdicts and finding ownership, while requiring authors to test inherited checks affected by additions; the [composition contract](../../implementation/okf-implementation-guide.md#57-composition) governs exact behavior.
