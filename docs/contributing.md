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
(cd packages/wayfinder && dart test --concurrency=2 --exclude-tags stress)
(cd packages/wayfinder && dart test --concurrency=2 --tags stress test/project/file_lock_test.dart)
dart run tool/generate_published_schemas.dart --check
python3 tool/ci/verify-configured-example.py
python3 tool/ci/verify-independent-profile.py
```

The quick core lane excludes only `stress`. The explicit stress lane above keeps
all 50 rounds of the real concurrent native flock/errno regression; run it when
locks change. CI runs both lanes on minimum Dart and stable, with the original
stress repetition count and timeout. Plain `dart test` still includes stress.

Embeddings has a separate explicit `native` lane. From
`packages/wayfinder_embeddings`, use:

```sh
dart test --concurrency=2 --exclude-tags native
# After preparing the pinned model and installing ObjectBox:
WAYFINDER_REQUIRE_NATIVE=1 dart test --concurrency=2 --tags native
```

Model/library presence never enables native tests by itself. The requirement
flag enables native inference, real ObjectBox persistence/migration and
installed-library verification; missing prerequisites then fail instead of
skipping. Without the flag, plain `dart test` skips native-tagged cases even if
assets remain installed. Fake-engine/CountingEmbedder tests and pure ObjectBox
schema/scoring checks remain in the model-free lane. The stable native job
selects tagged coverage and retains all bundle/integration/retrieval gates;
minimum/stable keep the complete model-free suite.

`dart run melos run lint` checks all workspace packages. Package test runs are
serialized because workspace members share native build-hook output; concurrent
runs can race during library copying or macOS codesigning. Use concurrency 2 for
the commands above and coordinate heavy invocations with other agents on the
machine; separate test invocations do not share that limit. For docs/skills, also
check local links and compare changed wording with its authoritative source. Report
what ran; validation checks conformance, not the judgment a skill asks for.

`packages/wayfinder_flutter` is outside the workspace and needs Flutter. Its
[README](../packages/wayfinder_flutter/README.md#development) lists its checks.

## Schemas and Profile packages

The engine embeds no Profile. It embeds only the two published schemas,
`docs/schemas/wayfinder.schema.json` and `docs/schemas/wayfinder-profile.schema.json`, through
the generated `packages/wayfinder/lib/src/generated/published_schemas.g.dart`. After editing
either schema, run `dart run tool/generate_published_schemas.dart` and commit the result;
`--check` is the CI gate for a stale file. The okf release and its index generator revision
come from okf itself (`okfVersion` and `okfIndexGeneratorRevision`), so the `okf:` constraint,
the same `^0.7.0-beta.1` in every package, is an ordinary range. Moving it to a new minor release
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
`wayfinder_embeddings` keeps `analyzer` out of its runtime dependencies;
`python3 tool/ci/verify-embeddings-closure.py` checks that rule in CI.
The committed baseline chunks are the source of truth for the judged retrieval
corpus. Its tools and tests replay the Dart chunks and compare against that
baseline without rewriting it; see its [fixtures README](../packages/wayfinder_embeddings/fixtures/README.md).

For native semantic retrieval, `dart run melos run wayfinder_embeddings:prepare` stages the pinned
25.28 MB model. `dart run melos run wayfinder_embeddings:build` creates a
CLI bundle containing the model and native libraries. The model choice is
recorded in [ADR-0009](adr/0009-local-knowledge-retrieval.md). `wayfinder validate` provides
bundle validation; search examples and evaluation commands live in the
[embedding package](../packages/wayfinder_embeddings/README.md#command-line-entry-points).


## Hosted runner policy

Source tests and native artifact verification currently run on Linux only to
limit compute usage; their macOS and Windows jobs are paused. Native
distribution is also paused because its release contract requires all three
platform archives; pub.dev publishing and Linux verification remain available.
The separate installer-script workflow checks PowerShell 7 and Windows
PowerShell 5.1 on installer pull requests. Public installer verification runs
automatically on Linux and supports manual macOS/Windows smoke tests against
the published release. These installer checks do not replace source tests or
verification of new native artifacts on those platforms.

Pull-request workflows use exactly `opened`, `synchronize`, `reopened`, and
`ready_for_review`. A draft pull request runs zero jobs: classification,
heavy work, light work, and the required check all stay skipped.
`ready_for_review` runs the suite once the pull request is ready. A ready
pull request whose diff is only non-code (documentation outside
`docs/schemas/`, readmes, licenses, issue and pull-request templates, and
non-build assets) skips the heavy jobs. The required check still runs and
succeeds. Schemas, examples, Profile skill text, version snapshots, and
test fixtures stay with the code jobs, because CI reads them.
Classification, the required check, and POSIX installer lint use
`ubuntu-slim`. Package tests and native retrieval stay on `ubuntu-latest`.

No pull request schedules a `macos-*` runner. macOS and Windows public-install
coverage is the manual dispatch added in #170. The workflow selects that
runner only for `workflow_dispatch`.


The `test` matrix analyzes all packages and runs model-free tests plus the
full core lock stress on Dart 3.11.0 and stable. The stable-only
`native-retrieval` job selects native-tagged model/ObjectBox integration and
keeps retrieval quality, relocated bundles and installer verification. This avoids
running that complete native pipeline twice per commit; native execution on
the minimum SDK is no longer a CI promise. Stable Linux artifacts still belong
to the exact tested commit, and the three-platform distribution remains paused.

Portable knowledge contracts and native loader regression tests now run in the
core suite (`test/knowledge/` and `test/project/knowledge/`). From `tool/ci`, run
`python3.13 verify-reader-closure.py` after `dart pub get`: it follows the actual
transitive import/export/part closure of `package:wayfinder/knowledge.dart`,
including every conditional branch, and rejects native/OKF/Flutter imports.
The existing `wayfinder.dart` and `project.dart` remain native entries; package
runtime dependencies are not confused with a portable entry's import closure.
The separate Flutter workflow tests the memory/local reader and graph suite
when core/Flutter sources change; Flutter stays outside the root workspace.
See [reader integration](../packages/wayfinder_flutter/doc/integration.md).
