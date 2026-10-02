---
name: assess-knowledge-bundle
description: Run a deliberate whole-bundle Profile assessment of knowledge/, automated validation plus every judgment check of each Profile in the bundle's chain, and emit the standard Profile Review Report. Use for audits, adoption checks, and structural reorganizations.
disable-model-invocation: true
---

# Assess Knowledge Bundle

A complete Profile assessment of the bundle at `knowledge/`, at whole-bundle
scope. The rules are not restated here. This skill is an entry point into the
`author-knowledge-bundle` skill's assessment reference, which owns Profile
Review for both scopes. If the user names another configured bundle, assess
that whole bundle with its own binding rather than assuming it inherits
`knowledge/`.

## Process

1. Collect automated validation with the command selection in the shared
   [assessment reference](../author-knowledge-bundle/references/profile-assessment.md).
   Record the OKF result, the Profile findings, the diagnostics, and the gate,
   even when no Profile can be selected. When the CLI is unavailable, record
   `NOT RUN` with the reason.
2. Load the skill of each Profile in `profile.chain`, root first, per
   [Load the Profile chain](../author-knowledge-bundle/SKILL.md#load-the-profile-chain).
   Do not modify the binding. If no Profile can be selected, skip step 3 and
   still complete step 4 with `Outcome: NEEDS HUMAN`.
3. Follow the assessment reference with **Scope: whole bundle**: every
   concept, and every check of every Profile skill's review map. Read the
   guidance each check links to as you judge it.
4. Emit the Profile Review Report in the interaction or pull request, never as
   a certificate inside the bundle. Fix clear defects within the requested
   scope and re-assess. A read-only assessment reports defects without
   editing. Escalate with `NEEDS HUMAN` per the assessment reference.
