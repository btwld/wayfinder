# Migrated contract prototypes from conceptadev/okf

Provenance: conceptadev/okf branch `feature/3-profile-layer-contracts`
(commit `c86d8cd`, PR conceptadev/okf#18, closed without merge on 2026-08-14).
The branch implemented the contract layer of the original combined spec before
the toolchain split. It was strictly profile-shaped work — `finding.dart`
hardcodes the `okf/`, `profile/`, and `profile/frontmatter-` namespaces, and
`profile.dart` is the manifest and declaration model — so the whole branch
moved here.

## Contents

- `lib/` — the changed library files at commit `c86d8cd`, verbatim.
- `profile_contract_test.dart` — the contract test suite, verbatim.
- `contracts-commit.diff` — the exact diff of the contracts commit, so the
  changes to pre-existing files (`index_generator.dart`, `okf.dart`) are
  visible without comparing against the okf history.

## Disposition — do not import as-is

- `profile.dart` (manifest model, rule activations, judgment declarations,
  `profile.yaml` declaration types) and its tests are the starting point for
  **#5** (contract: manifest model, bundle declaration, profile rule surface).
- `finding.dart`, `rule_catalog.dart`, `bundle_change_set.dart`, and
  `index_log.dart` are **reference only**. The base versions land in
  conceptadev/okf#3 with a namespace-generic ID grammar and an open
  registration seam; this package will consume them from the `okf` library
  once the bootstrap (#4) exists. The hardcoded three-namespace grammar in
  this copy of `finding.dart` predates that decision and is superseded.

Delete this directory once #5 has absorbed what it needs.
