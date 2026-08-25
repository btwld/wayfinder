# Changelog

Release history of the `okf_profile` Dart package (the `okfp` toolchain).
This is package semver; profile releases are recorded in `profile/`, not here.

## Unreleased

- Move the package to `packages/okf_profile/` under a pub workspace; git
  dependencies now need `path: packages/okf_profile`.
- Raise the SDK floor to 3.6.0 (workspace resolution requires it).

## 0.1.0

- Bootstrap the `okf_profile` package and the `okfp` command-line interface.
- Ship the closed `validate <bundle> [--output text|json]` automated gate for
  Concepta Profile 2026.2, backed by the independent OKF 0.2 result.
- Keep deterministic Profile findings, contextual judgment, and automated-gate
  states separate in stable text and JSON contracts.
