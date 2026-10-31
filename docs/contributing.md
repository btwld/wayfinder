# Contributing to Wayfinder

Read [AGENTS.md](../AGENTS.md) for authority, scope and routing. Use the driving
issue as scope, or state the maintenance scope in the PR. Record the real-use
driver; project-specific vocabulary belongs in that project's binding or bundle.

## Engine contract changes

A change to what a package is, how the engine reads or composes one, its
results, its diagnostics, or its builtins needs all of the following in the
same change:

1. A titled, dated entry or amendment in [ARCHITECTURE.md](../ARCHITECTURE.md),
   using 1–3 sentences for the choice, reason and cost; no new numbered ADR file.
2. The guide's §9 change-record entry naming affected sections, the real-use
   driver, and the migration impact for implementations and packages.
3. A package `format` bump when an existing package would read differently.
   Never reinterpret an old package silently.
4. Updated schemas, goldens, and the generic skills that teach the contract.

An upstream OKF **specification** release requires an engine compatibility
review in [`docs/compatibility-review.md`](compatibility-review.md) before
the engine reads it. An `okf` package release that changes what okf reports or
what its index generator writes needs a review row and a changelog entry that
names it as breaking for every Profile using `matches-generated`. Never claim
unreviewed compatibility.

## Profile changes

A Profile changes through its own release process, in its package. For
Bitwild, a rule or vocabulary change needs all of the following in the same
change:

1. The rule in `wayfinder-profile.json`, with `tests` that pass and fail, and
   a golden fixture that fires it.
2. A `### <rule-id>` heading with its rationale in the README.
3. A [`CHANGELOG.md`](../profiles/bitwild/CHANGELOG.md) entry naming the rules
   changed, the real-use driver, and migration impact in words: whether
   bundles that passed still pass, and what they must do if not.
4. A row in Bitwild's [compatibility review](../profiles/bitwild/compatibility-review.md)
   for each new or changed rule or declared key.
5. When the release is published, a new `release` value, a tag that never
   moves, and an immutable snapshot of the superseded package under
   `profiles/bitwild/versions/`.

Keep canonical paths and symbols stable. A Profile's release lives in its
package's `release` field, and the engine's in its pubspec and changelog, not
in filenames or symbol names. Only immutable snapshots, including vendored
OKF, carry versions in their names.

When a rule changes, search that Profile's skill for the old wording, starting
with its adoption seed. A validator cannot detect a skill teaching withdrawn
judgment. Keep the generic skill family Profile-agnostic; update `create-profile`
and its references with engine-contract changes.

## Checks

From the root, run the core checks used by [CI](../.github/workflows/ci.yml):

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages/wayfinder/lib packages/wayfinder/test
dart analyze --fatal-infos
(cd packages/wayfinder && dart test)
dart run tool/generate_published_schemas.dart --check
python3 tool/ci/verify-configured-example.py
python3 tool/ci/verify-independent-profile.py
```

`dart run melos run lint` checks all four packages. Package test runs are
serialized because workspace members share native build-hook output; concurrent
runs can race during library copying or macOS codesigning. Tests within each
package keep their normal concurrency. For docs/skills, also check
local links and compare changed wording with its authoritative source. Report
what ran; validation checks conformance, not the judgment a skill asks for.

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

## Formatting and documentation

Use Dart 3.11.0 or later. **Format with stable**, which defines CI's canonical
style; the floor SDK can format differently and is used for analysis/tests only.
For docs/skills, check local links and authoritative wording. Release-tool changes
also run `tool/release/` checks. Example validation covers conformance; review
skill judgment separately. See [releasing](releasing.md) for publication/binaries.

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
