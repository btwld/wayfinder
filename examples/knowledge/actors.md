---
type: Actor Registry
title: Actors
description: Actor IDs mapped to organization, side, and role.
status: stable
generated: { by: claude-code/opus-5, at: 2026-07-30T16:20:00Z }
---

Actor IDs are opaque and stable: affiliation is looked up here, never encoded into
the ID. Someone who changes organization gets a new row range, so historical
attributions stay true. An actor missing from this table reads as unknown — that
degrades a lookup, it never invalidates a concept.

`Side` is one of `client`, `internal`, `vendor`, `tool`, `unknown`. A third-party
authoring agent is `tool`; a process the project itself runs is `internal`.

| Actor ID | Name | Organization | Side | Role | Active |
|----------|------|--------------|------|------|--------|
| `human:chris` | Christiano Higuto | Concepta | internal | Engineering lead | 2026-01 – |
| `claude-code/opus-5` | — | Anthropic | tool | Authoring agent | 2026-06 – |
| `process:meeting-transcription` | — | Concepta | internal | Transcription process | 2026-03 – |
