# Contributing to Wayfinder

Read [`AGENTS.md`](../AGENTS.md) before contributing. Engine-contract and Profile
changes have separate requirements:

- **The engine contract** says what any Profile package is and how the engine reads it.
  It changes through an ADR and the guide's change record, and a change that would make an
  existing package read differently bumps the package `format`.
- **A Profile** changes through its own release process. A Bitwild rule earns its way in
  by being needed on a real corpus and by being generic. If it names a client, a domain, or
  a project's own vocabulary, it belongs in that project's binding or bundle. Each change
  has a [changelog](../profiles/bitwild/CHANGELOG.md) entry stating the **driver** and the
  migration impact.

Record the real-use driver so reviewers can distinguish a demonstrated need
from a preference.

Two rules govern every Profile edit. **Silence is deference.** Where a Profile says nothing
and OKF settles the point, follow OKF and do not mint a convention in its place. **Precedence
is a chain.** OKF wins over the engine contract, which wins over each Profile package.

## Checks

Run the [core contributor checks](../README.md#contributor-checks) from the
repository root. `dart run melos run lint` checks all three workspace packages.

## Schemas and Profile packages

The engine embeds no Profile. It embeds only the two published schemas,
`docs/schemas/wayfinder.schema.json` and `docs/schemas/wayfinder-profile.schema.json`, and the
okf package version, through the generated
`packages/wayfinder/lib/src/generated/published_schemas.g.dart`. The version comes from the
`okf:` constraint in `packages/wayfinder/pubspec.yaml`, which allows exactly one patch release
(`'>=0.5.0 <0.5.1'`; every package uses the same constraint), so the embedded value and the
resolved dependency cannot drift. pub rejects a bare version for a published
package. After editing either schema or changing the okf pin, run
`dart run tool/generate_published_schemas.dart` and commit the result;
`--check` is the CI gate for a stale file.

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

Developing the workspace requires Dart 3.11.0 or later. Run `dart pub get` at the
repository root, then `dart run melos run lint` to analyze, check formatting, and test all workspace
packages. Every package declares the same Dart 3.11.0 minimum, so one SDK serves
the whole workspace.

`wayfinder_embeddings` moved here from Orbit with its tests, fixtures, and BSD
license preserved in the package directory. See its [README](../packages/wayfinder_embeddings/README.md)
and the [retrieval documentation guide](wayfinder_embeddings.md) for the
implementation, evaluation runbook and recorded decisions. Its optional native
backend needs `dart run melos run objectbox:install`; regenerate its committed ObjectBox
files with `dart run melos run build` only when entity schemas change.

For native semantic retrieval, `dart run melos run wayfinder_embeddings:prepare` stages the pinned
25.28 MB model. `dart run melos run wayfinder_embeddings:build` creates a
CLI bundle containing the model and native libraries. See the
[local search implementation and measurements](wayfinder_embeddings_local_search.md).
The accepted model choice and next retrieval experiments are recorded in
[ADR-0009](adr/0009-local-knowledge-retrieval.md). `wayfinder validate` provides
bundle validation; search examples and evaluation commands live in the
[embedding package](../packages/wayfinder_embeddings/README.md#command-line-entry-points).
