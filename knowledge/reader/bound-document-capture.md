---
type: Architecture Decision Record
title: Bound document capture and inventory the rest
description: Only classified Markdown and configuration bytes are captured, and attachments and over-budget documents are inventoried with refusals.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: decision-bounded-capture
    title: Bounded document capture with attachment inventory
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#bounded-document-capture-with-attachment-inventory
---

# Decision

For the desktop reader's real attachment-heavy repository (4 MB knowledge plus
154 MB captures under a 32 MB capture budget), capture only classified Markdown
and project configuration/lock bytes, failing capture if either present input
cannot fit; inventory attachments and over-budget documents with size, modification
instant and per-file refusals. Share file identity between manifests and revisions,
excluding per-file refusal wording. Keep exact retained-byte reads
and metadata-only revisions for omitted files, refusing their reads and any
incomplete bundle graph; the cost is inventory-only attachments and inability
to detect their same-size/restored-mtime edits, with no OKF/Profile change.
