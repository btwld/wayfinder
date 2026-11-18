---
type: Guide
title: Regenerate schemas and goldens
description: When and how to regenerate the embedded schemas and each golden file.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:32:44Z
sources:
  - id: contributing
    title: Contributing to Wayfinder
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/contributing.md#schemas-and-profile-packages
---

# Schemas and Profile packages

The engine embeds no Profile. It embeds only the two published schemas,
`docs/schemas/wayfinder.schema.json` and `docs/schemas/wayfinder-profile.schema.json`, through
the generated `packages/wayfinder/lib/src/generated/published_schemas.g.dart`. After editing
either schema, run `dart run tool/generate_published_schemas.dart` and commit the result;
`--check` is the CI gate for a stale file. The okf release and its index generator revision
come from okf itself (`okfVersion` and `okfIndexGeneratorRevision`), so the `okf:` constraint,
the same `^0.7.0-beta.1` in every package, is an ordinary range. Moving it to a new minor release
can move the generator revision, which is a breaking engine change
([guide §5.6](../../implementation/okf-implementation-guide.md#56-rules-and-builtins)).

Profiles are fetched through `wayfinder get`, not embedded in the engine, so
editing a package needs no regeneration. This repository keeps Bitwild under
`profiles/bitwild/` and illustrative Profiles under `examples/profiles/`.
A package's shape is
`docs/schemas/wayfinder-profile.schema.json`. The engine runs every schema rule's `tests` when
it parses the package, so a rule whose examples disagree with its check never loads.
`profile_package_test.dart` and `profile_descriptors_test.dart` cover that boundary.

# Golden results

Regenerate only for intended contract/wording changes; review the diff in the
same change. Unexpected golden changes are regressions. From the owning package,
run `UPDATE_GOLDENS=1 dart test <test-path>`:

| Package / test path | Pins |
| --- | --- |
| `wayfinder` / `test/golden_test.dart` | Full fixture validation reports in `test/goldens/`. |
| `wayfinder` / `test/published_schema_wording_test.dart` | First-failure wording for single-defect schema mutations in `test/published_schema_wording/golden.json`. Frozen Bitwild/two-rule-child seeds make this independent of Profile/example edits. |
| `wayfinder_cli` / `test/golden_contract_test.dart` | MCP initialization/discovery (including 2026-07-28), project index/validate/search and single-bundle search outputs in `test/goldens/`. |

CLI/MCP goldens use a deterministic encoder, local Git Profile source and frozen
contract fixtures, not native retrieval or the live Bitwild release. They
normalize environment/version/timing details; adjacent tests check chunk identity
across locations. `mcp_dart`/`ack` upgrades can change discovery schemas and need
the same reviewed regeneration.
