# ADR-0008: Reuse OKF's finding report as the validator wire format

- Status: accepted
- Date: 2026-08-26
- Scope: validator report contract; originally implemented in `okfp`

## Context

OKF 0.2 replaced the earlier validator report, warning tier, and separate
bundle-load issue channel with ordered `OkfFinding` values in one `OkfReport`.
Reconstructing the old shape would lose OKF's identifiers and severity meanings.

## Decision

Publish OKF's report directly under `okf.report`. Load failures are findings
in that report, not a separate `okf.load_issues` array. Validate through
`OkfBundleLoadResult.validate()` and let OKF decide conformance without a
Profile-side strict mode or severity reinterpretation.

Profile findings use the same finding grammar and canonical ordering in the
stable `concepta-profile/<rule-slug>` namespace. Profile release and normative
rule references live in a Profile rule-descriptor table, not invented fields
in OKF's wire format. Keep OKF and Profile states distinct.

## Consequences

Consumers of the older `valid`, count, `diagnostics`, or `load_issues` fields
must read the findings array. The change was versioned in the original
`okf_profile` package; no compatibility projection of the old JSON is kept.
OKF advisories remain non-blocking. The four-part result and `BLOCKED BY OKF`
behavior from [ADR-0004](0004-closed-concepta-profile-validator.md) remain.
