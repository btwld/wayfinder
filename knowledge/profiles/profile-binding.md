---
type: Glossary Definition
title: Profile Binding
description: The project-root `wayfinder.json` entry that selects one Profile for a whole bundle and adds project vocabulary.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:23:07Z
sources:
  - id: glossary
    title: Wayfinder glossary
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/GLOSSARY.md
---

# Definition

The project-root `wayfinder.json` entry whose direct Git `source` and
`applies_to` paths select one Profile for a whole bundle, with the additive project
fields that [guide §4.7](../../implementation/okf-implementation-guide.md#47-project-binding-and-lock) lists. It cannot define or override
rules.

# Avoid

Rule manifest, per-directory Profile
