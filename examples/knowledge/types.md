---
type: Type Registry
title: Types
description: The standard and project-specific types available to this bundle.
status: stable
generated:
  by: claude-code/opus-5
  at: "2026-07-30T16:20:00Z"
---

Every concept's `type` resolves here. Kind is carried by `type` alone, never by a
directory name. Standard rows remain available even when unused; project-specific
rows follow them in lexical order.

| Type | Intended content |
|------|------------------|
| `Glossary Definition` | One project or domain term |
| `Business Rule` | One standing business rule, constraint, invariant, or policy |
| `Question` | One named unknown, with what is known, what is missing, and what would close it |
| `Request` | A durable request from any relevant source |
| `Analysis` | An investigation, feasibility study, comparison, or recommendation |
| `Decision` | A durable non-architectural decision with an independent lifecycle |
| `Architecture Decision Record` | An architectural decision in ADR form |
| `Architecture Document` | A durable description of the system architecture |
| `Specification` | A specification the project maintains as durable knowledge, not one a tracker owns the state of |
| `Guide` | Durable operational or engineering guidance |
| `Interaction Record` | An interaction whose combined context is itself durable |
| `Knowledge Profile` | The Concepta Profile and OKF release declaration |
| `Type Registry` | The standard and project-specific types available to the bundle |
| `Actor Registry` | Actor IDs mapped to identity, affiliation, role, and active period |
| `Meeting Transcript` | A mirrored verbatim transcript of a recorded interaction, held as an immutable snapshot |

`Meeting Transcript` is the one row here that is not from the Profile's standard
vocabulary (§5.2). A project MAY add a type, and MUST add it to this registry when
it does — which is what makes an invented type visible rather than passing as a new
kind of thing. It is a mirrored artifact under `references/`, never edited to
reflect later understanding.

# Relationships

- Depends on: [Concepta OKF Profile](/profile.md)
