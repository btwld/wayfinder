---
type: Architecture Decision Record
title: Write through one path with a delta gate
description: "One prepare, assess and commit path through okf: the whole candidate passes OKF, and the Profile may gain no error."
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: adr-0019
    title: "ADR-0019: Profile-aware writes"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#safe-writes-with-a-delta-gate-adr-0019-adr-0024-adr-0025
  - id: adr-0024
    title: "ADR-0024: Pin the generator revision, and relock offline"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#safe-writes-with-a-delta-gate-adr-0019-adr-0024-adr-0025
  - id: adr-0025
    title: "ADR-0025: Give a host the adoption seams it runs"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#safe-writes-with-a-delta-gate-adr-0019-adr-0024-adr-0025
---

# Decision

Keep one prepare/assess/commit path through okf's projection seam, because raw host edits bypassed Profile-generated indexes and caller-authored history; rewrite only indexes whose generated text changes and reject stale bundle/configuration inputs, even for empty commits.
The whole candidate must pass OKF, but Profile acceptance is a delta with no introduced errors: old errors or an unassessed Profile may remain, so callers needing conformance still require the full gate and may move the shared assessor to a bounded isolate.
Hosts must serialize relock/get with writes because no lock spans both checks; canonical serialization, leftover lock files and possible rollback failure are costs described in the [authoring API](../../packages/wayfinder/README.md#authoring).
