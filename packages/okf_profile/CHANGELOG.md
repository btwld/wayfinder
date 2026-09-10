# Changelog

## 0.2.1-dev.0

- Expose the existing validator and result contracts for Wayfinder without changing
  `okfp` commands, validation semantics or exit codes.

Release history of the `okf_profile` Dart package (the `okfp` toolchain).
This is package semver; profile releases are recorded in `profile/`, not here.

## 0.2.0

- Migrate to okf 0.2.0 and adopt its finding contract as the wire format
  (ADR-0008): the `okf.report` JSON object is now okf's own projection — a
  canonically ordered `findings` array of `{id, severity, message, location}`
  objects with namespaced kebab-case IDs — and the separate `okf.load_issues`
  channel is retired, because load failures are error-severity findings in the
  same report.
- Text output reports the OKF component as `N error(s), N advisory(ies)`;
  the `warning` tier no longer exists upstream.
- `ProfileValidator` validates through okf's single report-composition seam
  (`OkfBundleLoadResult.validate()`) and no longer takes an okf validator.
- Profile findings speak the same finding grammar (ADR-0008): each JSON
  finding is the okf projection — `{id, severity, message, location}` — plus
  the `profile_release` and `rule` references guide §4.2 requires, and
  findings sort in okf's canonical report order (path, line, column, id,
  severity, message) instead of emission order.
- Add the profile rule descriptor registry (id, severity, normative rule
  reference), mirroring okf's `okfSpecRuleDescriptors`. Every finding is
  built from its rule's descriptor, so id, severity, and rule reference
  cannot drift from the registry — a call site names only the rule, the
  observation, and its path — and a corpus test holds every emitted finding
  to a registered rule.
- The automated gate's exit codes are okf's `OkfExitCode` contract:
  `success`/`findings`/`usage` for PASS/FAIL/UNSUPPORTED (values unchanged).
- Index and log parsing go through okf's `OkfIndexDocument`/`OkfLogDocument`
  entry format instead of a hand-rolled markdown-AST parallel; ADR-0007's
  percent-decoded target comparison is unchanged on top of it. okf 0.2.0's
  angle-bracket destination form means a raw `)` no longer forces the
  percent-encoded spelling; the authoring skill teaches both. The §9 expected
  projection stays profile-owned — okf's generic index generator synthesizes
  directory descriptions the Concepta projection deliberately leaves empty.

## 0.1.1

- Enforce the Profile 2026.1 `raw/` tier amendment (ADR-0006): non-index
  markdown under a `raw/` directory in `references/` fails deterministically
  as `concepta-profile/raw-directory-markdown`, and a `raw/` directory sitting
  directly under `references/` fails as
  `concepta-profile/raw-directory-placement` — the tier is per source
  directory, and `references/` itself is not one.

## 0.1.0

- Bootstrap the `okf_profile` package and the `okfp` command-line interface,
  as a pub workspace member at `packages/okf_profile/`.
- Ship the closed `validate <bundle> [--output text|json]` automated gate for
  the Concepta Profile, backed by the independent OKF 0.2 result.
- Keep deterministic Profile findings, contextual judgment, and automated-gate
  states separate in stable text and JSON contracts.
