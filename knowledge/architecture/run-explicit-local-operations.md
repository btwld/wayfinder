---
type: Architecture Decision Record
title: Run explicit local operations from one CLI
description: One CLI validates, indexes and searches; no command downloads a model or rebuilds an index implicitly.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: adr-0010
    title: "ADR-0010: One CLI validates, indexes, and searches local knowledge"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#explicit-local-cli-operations-adr-0010
---

# Decision

Provide one CLI for validation, explicit indexing and cited search so retrieval remains inspectable and separate from Profile conformance; runtime commands never download/train models or implicitly rebuild indexes.
This requires users to reindex after edits and retain derived local copies of bundle text; [Keep indexes as plain-file generations](../retrieval/publish-indexes-as-immutable-generations.md) replaces the original ObjectBox storage and permits previous snapshots during refresh, while [the CLI guide](../../packages/wayfinder_cli/README.md) owns current commands.
