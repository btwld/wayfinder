# Contributing to Wayfinder

Read [`AGENTS.md`](../AGENTS.md) before contributing. It owns the
[engine-contract change requirements](../AGENTS.md#changing-the-engine-contract)
and the separate [Profile release process](../AGENTS.md#changing-a-profile),
including real-use evidence, OKF precedence, and migration records.

## Checks

Use Dart 3.11.0 or later. Run the
[core contributor checks](../README.md#contributor-checks) from the repository
root; `dart run melos run lint` checks all four workspace packages.
Package test runs are serialized because workspace members share native
build-hook output; concurrent runs can race during library copying or macOS
codesigning. Tests within each package keep their normal concurrency.

## Schemas and Profile packages

The engine embeds no Profile. It embeds only the two published schemas,
`docs/schemas/wayfinder.schema.json` and `docs/schemas/wayfinder-profile.schema.json`, through
the generated `packages/wayfinder/lib/src/generated/published_schemas.g.dart`. After editing
either schema, run `dart run tool/generate_published_schemas.dart` and commit the result;
`--check` is the CI gate for a stale file. The okf release and its index generator revision
come from okf itself (`okfVersion` and `okfIndexGeneratorRevision`), so the `okf:` constraint,
the same `^0.5.1` in every package, is an ordinary range. Moving it to a new minor release
can move the generator revision, which is a breaking engine change
([guide §5.6](../implementation/okf-implementation-guide.md#56-rules-and-builtins)).

Profiles are fetched through `wayfinder get`, not embedded in the engine, so
editing a package needs no regeneration. This repository keeps Bitwild under
`profiles/bitwild/` and illustrative Profiles under `examples/profiles/`.
A package's shape is
`docs/schemas/wayfinder-profile.schema.json`. The engine runs every schema rule's `tests` when
it parses the package, so a rule whose examples disagree with its check never loads.
`profile_package_test.dart` and `profile_descriptors_test.dart` cover that boundary.

## Golden results

`packages/wayfinder/test/golden_test.dart` pins every fixture's full validation result in
`packages/wayfinder/test/goldens/`. When a change is meant to alter findings, regenerate them
from `packages/wayfinder` with `UPDATE_GOLDENS=1 dart test test/golden_test.dart` and review
the golden diff with the change. An unexpected golden diff is a regression.
`published_schema_wording_test.dart` likewise pins, in
`packages/wayfinder/test/published_schema_wording/golden.json`, the message for
every single-defect mutation of its seeds that fails its published schema. The
seeds are frozen copies of the Bitwild example's `wayfinder.json`, the Bitwild
package and the `two-rule-child` package, so editing a Profile or an example
leaves the golden alone. Regenerate it with the same `UPDATE_GOLDENS=1` only
after an intended wording change.

`packages/wayfinder_cli/test/golden_contract_test.dart` pins the CLI and MCP
output contracts in `packages/wayfinder_cli/test/goldens/`: the MCP
`initialize` result and `tools/list`, and the same pair under MCP 2026-07-28
(`server/discover`); project `index` JSON; MCP project `validate`, checked
against each bundle's CLI JSON; the MCP project search Markdown; and CLI
search JSON for the project and for one bundle. It runs the project in
`test/fixtures/contract-project/` with a deterministic test encoder and binds
the frozen Profile in `test/fixtures/contract-profile/` from a local Git
source, so a Bitwild release leaves these goldens alone. It normalizes
temporary paths, the index key, chunk IDs, the Profile commit, the server
version, the okf release in `engine.okf` (checked against `okfVersion`) and
timings; a test beside them checks that the project indexed elsewhere gets
the same chunk IDs. The goldens need no native library, so every CI job runs
them. Regenerate from `packages/wayfinder_cli`
with `UPDATE_GOLDENS=1 dart test test/golden_contract_test.dart` only for an
intended contract change, and review the diff with it. `mcp_dart` and `ack`
serialize the MCP results and input schemas, so upgrading either can move
`tools_list.json` too; that upgrade needs the same reviewed regeneration.

## Formatting and documentation

**Format with a `stable` SDK, not with the declared floor.** `dart format`'s output is
version-dependent and its style is gated on the package's language version, so a floor
SDK and a newer stable can disagree on the same file. CI checks formatting on `stable`
only — that is what defines the canonical style — while the floor job still analyzes and
tests. Formatting with the floor SDK can produce output CI rejects.

For skill or documentation changes, also check local links and compare changed
rule wording with its authoritative source. Release-tool changes additionally
use the checks under `tool/release/` in CI. Example-gate success covers the
Profile's rules; the judgment its skill asks for is reviewed separately.

See the [release guide](releasing.md) for package publication and native binaries.

## Dart workspace development

`wayfinder_embeddings` keeps its tests, fixtures, and BSD license in the
package directory. See its [README](../packages/wayfinder_embeddings/README.md)
for the implementation and evaluation commands. Its optional native
`ObjectBoxStore` backend, which the knowledge store and the `wayfinder` command
do not use, needs `dart run melos run objectbox:install`; regenerate its committed ObjectBox
files with `dart run melos run build` only when entity schemas change. The root
`pubspec.yaml` overrides Dart `objectbox` to the version the installer pins
natively; change the override, the installer and
`tool/objectbox_assets/manifest.json` together.
`wayfinder_dart_chunker` holds the analyzer-based Dart chunker, so
`wayfinder_embeddings` does not depend on `analyzer`. Nothing in
`wayfinder_embeddings` may depend on it, including as a dev dependency.
`python3 tool/ci/verify-embeddings-closure.py` checks both rules in CI. The
chunker's tests also check the Dart chunks that the judged retrieval corpus
replays, and write that corpus golden; see
its [README](../packages/wayfinder_dart_chunker/README.md#development).

For native semantic retrieval, `dart run melos run wayfinder_embeddings:prepare` stages the pinned
25.28 MB model. `dart run melos run wayfinder_embeddings:build` creates a
CLI bundle containing the model and native libraries. The model choice is
recorded in [ADR-0009](adr/0009-local-knowledge-retrieval.md). `wayfinder validate` provides
bundle validation; search examples and evaluation commands live in the
[embedding package](../packages/wayfinder_embeddings/README.md#command-line-entry-points).
