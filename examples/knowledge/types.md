---
type: Type Registry
title: Types
description: The concept types this bundle uses.
status: stable
generated: { by: claude-code/opus-5, at: 2026-07-30T16:20:00Z }
---

Every concept's `type` resolves here. Kind is carried by `type` alone, never by a
directory name. Add a row before using a new type.

| Type | Intended content |
|------|------------------|
| `Knowledge Profile` | The profile declaration |
| `Type Registry` | This registry |
| `Actor Registry` | Actor IDs mapped to organization, side, and role |
| `Request` | A durable request from any relevant source |
| `Analysis` | An investigation, feasibility study, comparison, or recommendation |
| `Meeting Transcript` | A mirrored verbatim transcript of a recorded interaction, held as an immutable snapshot |

`Meeting Transcript` is the one row here that is not from the profile's default
vocabulary (§5.2). A project MAY add a type, and MUST add it to this registry when
it does — which is what makes an invented type visible rather than passing as a new
kind of thing. It is a mirrored artifact under `references/`, never edited to
reflect later understanding.

# Relationships

- Depends on: [Concepta OKF Profile](/profile.md)
