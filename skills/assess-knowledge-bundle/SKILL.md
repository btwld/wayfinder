---
name: assess-knowledge-bundle
description: Run a deliberate whole-bundle Profile assessment of knowledge/ — automated validation plus every contextual judgment rule — and emit the standard Profile Review Report. Use for audits, adoption checks, release upgrades, and structural reorganizations.
disable-model-invocation: true
---

# Assess Knowledge Bundle

A complete Profile assessment of the bundle at `knowledge/`, at whole-bundle
scope. The rules are not restated here: this skill is an entry point into the
`author-knowledge-bundle` skill's assessment reference, which owns Profile
Review for both scopes.

## Process

1. Read [`../author-knowledge-bundle/SKILL.md`](../author-knowledge-bundle/SKILL.md)
   and perform its release dispatch — this skill likewise implements only
   `concepta_profile: "2026.2"` with `okf_version: "0.2"`, and an unsupported
   declaration is reported, never assessed.
2. Run `dart run okf_profile:okfp validate knowledge` when available and record
   its result. It exposes the OKF result, the deterministic Profile result, and
   leaves judgment rules `UNASSESSED` — those are what the rest of this
   assessment supplies. When the CLI is unavailable, record `NOT RUN` with the
   reason; never substitute your own guess for a deterministic result.
3. Follow
   [`../author-knowledge-bundle/references/profile-assessment.md`](../author-knowledge-bundle/references/profile-assessment.md)
   with **Scope: whole bundle** — every contextual rule, every concept, using
   its review map to enumerate the surface. Read the other references there as
   each rule needs them.
4. Emit its Profile Review Report in the interaction or pull request, never as
   a certificate inside the bundle. Fix clear defects and re-assess; escalate
   with `NEEDS HUMAN` per the assessment reference.

Automated success is not complete Profile conformance, and this assessment does
not reinterpret the automated result: complete assessment is the combination of
both, which is exactly what the report records.
