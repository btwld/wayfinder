---
name: assess-knowledge-bundle
description: Run a deliberate whole-bundle Profile assessment of knowledge/ — automated validation plus every contextual judgment rule — and emit the standard Profile Review Report. Use for audits, adoption checks, and structural reorganizations.
disable-model-invocation: true
---

# Assess Knowledge Bundle

A complete Profile assessment of the bundle at `knowledge/`, at whole-bundle
scope. The rules are not restated here: this skill is an entry point into the
`author-knowledge-bundle` skill's assessment reference, which owns Profile
Review for both scopes.

## Process

1. Read [`../author-knowledge-bundle/SKILL.md`](../author-knowledge-bundle/SKILL.md)
   and determine release support without modifying the declaration. Unsupported
   contextual rules are never applied, but release dispatch does not skip step 2.
2. Collect automated validation using the command selection in the shared
   [assessment reference](../author-knowledge-bundle/references/profile-assessment.md).
   Record the independent OKF result, deterministic Profile result, and automated
   gate even when the release is unsupported or the declaration is defective.
   When the CLI is unavailable, record `NOT RUN` with the reason; never substitute
   a guess for a deterministic result. If release dispatch was unavailable or
   unsupported, skip step 3; still complete step 4. The report's Automated gate
   records the collected result, Reviewed notes that contextual review was not
   performed, and Outcome is `NEEDS HUMAN`. Unsupported capability or an
   unreadable declaration is not a 2026.2 judgment failure.
3. Follow
   [`../author-knowledge-bundle/references/profile-assessment.md`](../author-knowledge-bundle/references/profile-assessment.md)
   with **Scope: whole bundle** — every contextual rule, every concept, using
   its review map to enumerate the surface. Read the other references there as
   each rule needs them.
4. Emit its Profile Review Report in the interaction or pull request, never as
   a certificate inside the bundle. Fix clear defects within the user's requested
   scope and re-assess; a read-only assessment reports defects without editing.
   Escalate with `NEEDS HUMAN` per the assessment reference.
