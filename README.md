# Concepta repo template (Claude structure)

A starter repo with the Concepta technical-registry structure and no project code.
Create a new repo from this template ("Use this template" on GitHub), then start adding
specs and code. The repo is the source of truth for technical assets; business, sensitive,
and client data live in the MS 365 business registry, never here.

## What is in here
- AGENTS.md : the agent's entry point (repo rules + pointer to Ways of Working)
- docs/INDEX.md : read-first index of the docs
- docs/CONTEXT.md : domain glossary / shared language (SBVR skill can generate this)
- docs/ways-of-working.md : the shared process, canonical here, mirrored to MS 365
- docs/specs/ : one spec per feature (template + example)
- docs/adr/ : architecture decision records (template + example)
- docs/rfcs/ : RFCs (template)
- skills/ : where the shared skill bundle installs (plugin / Workspace Registry)
- .github/ : issue templates (bug, feature, feedback) and a PR template

## How to use
1. Create a new repo from this template.
2. Install the shared skills bundle (Claude Code plugin marketplace now; Stargate Workspace
   Registry, RFC #224, later).
3. Fill CONTEXT.md as you learn the domain.
4. Work the flow in docs/ways-of-working.md: capture as an issue, spec, tickets, build, review, done.
# repo-template
