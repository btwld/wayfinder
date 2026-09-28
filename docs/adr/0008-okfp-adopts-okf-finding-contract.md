# ADR-0008: okfp adopts the okf 0.2.0 finding contract as its wire format

- Status: accepted
- Date: 2026-08-26

## Context

okf 0.2.0 replaced its 0.1.x validation surface. `OkfValidator`,
`OkfValidationReport` (with `isValid`, `errorCount`, `warningCount`,
`diagnostics`), and the separate bundle-load-issue channel are gone. In their
place is one finding contract: `OkfFinding` values with frozen namespaced
kebab-case identifiers (`okf/<code>`), a two-tier `error`/`advisory` severity
model, an `OkfReport` that holds findings in one canonical order (path, line,
column, ID, severity, message), and a single composition seam —
`OkfBundleLoadResult.validate()` — that merges load-time failures into the
same report as validator findings, each as an error-severity finding.

okfp's JSON contract embedded the old shapes verbatim: an `okf.report` object
with `valid`/`error_count`/`warning_count`/`diagnostics`, and a separate
`okf.load_issues` array. Neither can be synthesized faithfully from 0.2.0
output — the identifiers changed grammar and namespace, the `warning` tier no
longer exists, and the load channel no longer exists as a distinct thing.

## Decision

- **okfp republishes okf's own projection.** The `okf.report` JSON object is
  `OkfReport.toJson()` — a canonically ordered `findings` array of
  `{id, severity, message, location}` objects — and the text output renders
  the same findings through okf's one-line form. `okf.load_issues` is
  retired; a file that failed to load is an error finding in the same report.
  ADR-0004's preservation rule is unchanged in meaning and stronger in
  mechanism: the OKF Report is passed through byte-for-structure, never
  reassembled.
- **Validation goes through the one seam.** `ProfileValidator` calls
  `OkfBundleLoadResult.validate()` and consumes the returned
  `OkfSpecValidation`; OKF conformance is its `isConformant` — no
  error-severity finding in the merged report. okfp holds no okf validator of
  its own.
- **okfp always judges the OKF report non-strict.** The guide forbids a
  `--strict` switch on okfp; consistently, an okf advisory never fails OKF
  conformance, the automated gate, or the exit status.
- **Profile findings adopt the same grammar (implementation to follow).**
  `concepta-profile/<rule-slug>` already conforms to okf's frozen finding-ID
  grammar. Profile findings become `OkfFinding` values in that namespace,
  with location capability, sharing the canonical report ordering and text
  form. The Profile-release and normative-rule references required by guide
  §4.2 move to a profile-side rule descriptor table (mirroring
  `okfSpecRuleDescriptors`), so per-finding metadata that okf's model has no
  slot for lives with the rule rather than in a divergent wire shape.
- **The break is versioned, not hidden.** The `okf_profile` package moves to
  0.2.0. Consumers of okfp JSON key on `id` values and the `findings` array
  from here on; no compatibility projection of the 0.1.x shapes is offered.

## Consequences

- CI consumers and scripts reading `okf.report.valid`, the count fields, or
  `okf.load_issues` must move to the `findings` array. The state fields
  (`okf.state`, `profile.state`, `judgment_rules.state`,
  `automated_gate.state`) and exit codes are unchanged.
- okf severity re-tiering flows through unfiltered: rules okf downgraded to
  advisory in 0.2.0 no longer block Profile assessment, which is okf's call
  to make, not the profile's (AGENTS.md: OKF wins over the profile).
- The four-component result model, `BLOCKED BY OKF` short-circuit, exit-code
  meanings, and the no-suppression/no-strict stances of ADR-0004 and guide
  §4.1–§4.2 are unchanged.
- Guide §4.1's wording is restated over the finding contract in the same
  change (a toolchain-facing clarification, not a profile rule change).
