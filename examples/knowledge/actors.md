---
type: Actor Registry
title: Actors
description: Actor IDs mapped to identity, affiliation, role, and active period.
status: stable
generated:
  by: claude-code/opus-5
  at: "2026-07-30T16:20:00Z"
---

Actor IDs are opaque and stable: affiliation is looked up here, never encoded into
the ID. Multiple rows preserve non-overlapping affiliation history, resolved at an
event timestamp. Unknown affiliation stays explicit and never changes OKF's actor
string or trust tier.

`Side` is one of `client`, `internal`, `vendor`, `tool`, `unknown`. `Active` uses
inclusive-start, exclusive-end ISO dates. A third-party authoring agent is `tool`;
a process the project itself runs is `internal` while the project operates it.

| Actor ID | Name | Organization | Side | Role | Active |
|----------|------|--------------|------|------|--------|
| `human:chris` | Christiano Higuto | Concepta | internal | Engineering lead | 2026-01-01 – |
| `claude-code/opus-5` | Claude Code | Anthropic | tool | Authoring agent | 2026-06-01 – |
| `process:meeting-platform` | Meeting platform recording | unknown | unknown | Recording process | unknown |
| `process:meeting-transcription` | Meeting transcription | Concepta | internal | Transcription process | 2026-03-01 – 2026-08-01 |
| `process:meeting-transcription` | Meeting transcription | Example Transcription Vendor | vendor | Transcription process | 2026-08-01 – |
