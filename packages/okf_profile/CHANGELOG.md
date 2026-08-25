# Changelog

Release history of the `okf_profile` Dart package (the `okfp` toolchain).
This is package semver; profile releases are recorded in `profile/`, not here.

## 0.1.0

- Bootstrap the `okf_profile` package and the `okfp` command-line interface,
  as a pub workspace member at `packages/okf_profile/`.
- Ship the closed `validate <bundle> [--output text|json]` automated gate for
  the Concepta Profile, backed by the independent OKF 0.2 result.
- Keep deterministic Profile findings, contextual judgment, and automated-gate
  states separate in stable text and JSON contracts.
