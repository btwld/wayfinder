# Agent instructions (repo)

You are working in a Concepta repo. Read this file first, then the relevant spec in
docs/specs, the docs/INDEX, and the issue's acceptance criteria before acting.

## Ways of working (shared, process)
The org Ways of Working is the process layer (intake to triage to spec to tickets to
implement to review to done). Canonical copy: docs/ways-of-working.md in this repo.
Human-readable mirror: the MS 365 business registry.

## Technical structure (this repo)
- docs/specs/ : one spec doc per feature (the PRD equivalent)
- docs/adr/   : architecture decision records (the decisions that persist)
- docs/rfcs/  : RFCs
- docs/CONTEXT.md : the domain glossary / shared language
- docs/INDEX.md : short description of each doc (read this first to save tokens)
- skills/     : the skill set (grill, to-spec, to-tickets, implement, tdd, code-review)
- issues + Project board : the work items and priority

## Rules
- The issue is your task, the spec is your context, the validation gate is your check.
- Propose a PR that references the issue and updates the spec in the same change.
- Do not widen scope beyond the issue. If anything is unclear, ask rather than assume.
- Store nothing of the client's; read client data live and read-only via an MCP.
