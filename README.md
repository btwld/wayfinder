# Wayfinder

Wayfinder checks, connects, and serves your project's knowledge. It validates an
OKF bundle with okf, then runs a static-analysis engine over it with the rules
of a Profile you choose. A Profile is a package of rules and vocabulary, written
as data, that adds your team's conventions to OKF while every bundle stays
readable by any OKF tool. Bitwild is the first Profile, and you can write your
own with or without it. Results come out as text, JSON, or SARIF, and `--fix`
writes okf's generated indexes.

The same bundle feeds local semantic search, a link graph, and an MCP server for
coding agents.

Source code, plugin files, documentation and binary releases live together in
this public repository. Install the complete native runtime to use Wayfinder
without a Dart SDK. On macOS Apple Silicon or Linux x64:

```sh
curl -fsSL https://raw.githubusercontent.com/btwld/wayfinder/main/tool/install.sh | sh
```

On Windows x64, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/btwld/wayfinder/main/tool/install.ps1 | iex
```

The [installation guide](docs/install.md) covers plugin setup,
upgrades and troubleshooting.
[GitHub releases](https://github.com/btwld/wayfinder/releases) contain the
complete runtime bundles; the [Dart package guide](packages/wayfinder_cli/README.md)
covers library dependencies and source development.

## How it works

Point Wayfinder at an explicit OKF bundle in your project:

```sh
wayfinder validate knowledge
wayfinder index knowledge
wayfinder search knowledge "How is reporting implemented?"
```

Validation checks OKF and the rules of the configured Profile. Indexing reads
its documents, computes embeddings locally and saves a local search index.
Search reuses that index and embeds only the query, returning passages with
source paths and line ranges. Run `index` again after editing the bundle;
unchanged content reuses its vectors. The complete installation includes the
model and native libraries, so retrieval needs no external embedding service.

`wayfinder mcp knowledge` exposes `validate`, `index`, `search` and `graph` to
coding agents. The Claude Code plugin configures this server and supplies the
author, adopt and assess skills. `wayfinder validate` provides Profile
validation; `wayfinder graph` projects the ordinary OKF relationship graph,
plus typed `relationships` edges beside it (JSON, or Mermaid/DOT text for an
external preview). `wayfinder_embeddings` is
the reusable Dart retrieval library. Upstream `okf` write and concept-authoring
tools remain separate capabilities.

## Profiles

A Profile is what `wayfinder validate` enforces. Each one is a directory at one
Git revision holding `wayfinder-profile.json`: its identity, its OKF binding, its
vocabulary, and its rules. It can also ship a README that explains each rule
and a skill that carries the judgment no rule can decide. A project names the
Profile it uses in `wayfinder.json`, and `wayfinder get` pins it in
`wayfinder.lock`. A bundle conforms to a Profile when `wayfinder validate` with
that Profile selected ends with the gate `PASS`.

Every Profile only adds to OKF. OKF runs first, and its result stands on its
own. A Profile can build on another through `extends` in its package, but no
Profile is a base. The [engine contract](implementation/okf-implementation-guide.md#5-profile-packages)
says what every package must meet, and the `create-profile` skill writes one.

[Bitwild](profiles/bitwild/README.md) is the first Profile. It keeps durable
project knowledge as an [Open Knowledge Format][okf] bundle beside the code:
which knowledge earns a concept, where it lives, and how it links to the
systems where work happens. Its release is **2026.3**, profiling **OKF 0.2
exactly**. Its [changelog](profiles/bitwild/CHANGELOG.md) records each release
and its migration. Bitwild 2026.2 bundles keep validating on wayfinder 0.1.x.

[okf]: https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing

## The dividing line

Everything in this repository is **company-generic**: it holds reusable ways of working.

A project's `knowledge/` bundle holds *what we know about that project* — its domain, its
decisions, its open questions. Nothing here is ever a prerequisite for reading one. A bundle
must stay readable on its own when a client receives only their project repository, so a
Profile is referenced from `wayfinder.json` and pinned by the lock, never copied in.

That is why this repository is consumed rather than vendored: install the skills once, pin
the `wayfinder validate` gate, and let each project repository carry only its own knowledge.

## Dart package migration

The `wayfinder` package is now the core validation library (formerly
`okf_profile`). Install `wayfinder_cli` for the `wayfinder` command and MCP server.
The embeddings library remains `wayfinder_embeddings`. Core 0.1.0 and the
CLI and embeddings 0.1.1 are published. The next prepared releases are CLI 0.1.2
and embeddings 0.2.0; see [release status and upgrade notes](docs/releasing.md#prepared-releases-embeddings-020-and-cli-012).
See [migration instructions](docs/install.md#migrate-the-dart-application-package).

## What is in here

| Path | Holds |
| --- | --- |
| [`implementation/`](implementation/) | The engine contract: Profile packages, adoption, index generation, validation, and distribution |
| [`profiles/bitwild/`](profiles/bitwild/) | The Bitwild Profile package: its rules, README, changelog, skill, and archived releases |
| [`skills/`](skills/) | Wayfinder's generic agent skills to author, adopt, assess, and search a bundle, and to create a Profile, shipped as the `wayfinder` plugin |
| [`packages/wayfinder_cli/`](packages/wayfinder_cli/) | Local CLI and MCP server for validation, graph projection, persistent embedding indexes and semantic search |
| [`packages/wayfinder_embeddings/`](packages/wayfinder_embeddings/) | Chunking, BM25 and dense retrieval utilities, with memory and optional ObjectBox storage |
| [`examples/`](examples/) | A complete worked bundle you can read end to end, and two small Profiles |
| [`packages/wayfinder/`](packages/wayfinder/) | Core validation library and its tests |
| [`tool/`](tool/) | CI and release tooling |
| [`docs/`](docs/index.md) | Glossary, architecture decisions, compatibility evidence, operations, and historical engineering evidence |
| [`AGENTS.md`](AGENTS.md) | Instructions for contributing to this repository |

## Getting started

### 1. Install the skills

The skills live in [`skills/`](skills/). The [native installer](docs/install.md)
installs them with the runtime: through the `wayfinder` plugin when the `claude`
CLI is available, and in `~/.agents/skills` for agents such as Codex.
`wayfinder update` refreshes them with the runtime, and `wayfinder setup` adds
the MCP server to a project's `.mcp.json`. To install the plugin in Claude Code
yourself:

First [install the complete Wayfinder runtime](docs/install.md). Run
Claude Code from the consuming project with a `knowledge/` bundle, or set
`WAYFINDER_KNOWLEDGE_DIR` to its explicit path before launching Claude Code.
The plugin registers Wayfinder's local MCP server; search and indexing require
the complete native/model installation. `WAYFINDER_EXECUTABLE` can select a
binary outside `PATH`.

```
/plugin marketplace add btwld/wayfinder
/plugin install wayfinder@wayfinder
```

For an existing installation, follow the [plugin migration sequence](docs/install.md#migrate-an-existing-plugin-installation): uninstall the old plugin and remove its marketplace registration before adding the public repository. This leaves one enabled skill family and MCP server.

Copying or symlinking the skill directories into `~/.claude/skills/` also works — install
the family as a unit, since the skills reference each other by sibling path. Symlinking is
the better fallback: the skills are versioned with the engine they describe, and a copy
silently ages past it. See [skills/README.md](skills/README.md) for the full set and what
each one does.

These skills are wayfinder's own and install once per machine. A Profile's skill is
different: it ships in the Profile package, and `wayfinder get` installs it into the
project's `.claude/skills/<id>/` and `.agents/skills/<id>/` at the commit the lock pins.
Commit those directories with the lock. See
[Profile skills](docs/wayfinder-configuration.md#profile-skills).

### 2. Set up a project repository

In the repository where you want to adopt a Profile, run:

```
/adopt-knowledge-bundle
```

It is prompt-driven: it explores what the repository already has and applies the
requested setup, asking when an unresolved choice or conflict needs your input.
It preserves existing bundles and seeds `wayfinder.json` plus the new bundle's
`index.md` and `log.md` under `knowledge/`, then writes the `AGENTS.md` blocks
that point agents into the bundle.
It then runs validation and the Profile skill's review, reporting any unavailable
check before claiming completion. Issue-tracker and triage-label setup are out of
its scope.

**It creates no directories under `knowledge/`, and that is correct.** Under Bitwild a
directory names a *subject*, and setup has no corpus from which to judge one (see
Bitwild's [structure guidance](profiles/bitwild/skill/references/structure.md)). A repository whose `knowledge/` is only its root files is fully set up, not
half-finished — the tree grows out of what the project actually learns rather than
a guess made on day one. A genuine subject area may be small; no numeric threshold
decides it.

### 3. Work the flow

Once a repository is set up, the skill family covers the bundle's whole lifecycle:

| Skill | Invocation | What it does |
| --- | --- | --- |
| `author-knowledge-bundle` | model-invoked | Creates, edits, moves, deprecates, and mirrors bundle content, and reviews the result. Agents reach it automatically before changing `knowledge/` or when asked for Profile Review |
| `adopt-knowledge-bundle` | user-invoked | Seeds the bundle and points agents at it (step 2 above) |
| `assess-knowledge-bundle` | user-invoked | Deliberate whole-bundle assessment, emitting the Profile Review Report |
| `use-wayfinder` | model-invoked | Searches, indexes and validates the bundle with Wayfinder. Agents reach it when a question may be answered by recorded knowledge, and answer from verified, cited passages |
| `create-profile` | user-invoked | Creates or revises a Profile package: interviews its author, writes rules with tests and the Profile's skill, and proves both |

You do not need to invoke `author-knowledge-bundle` yourself. It is model-invoked so
authoring mechanics and each Profile's skill are loaded before a bundle write or a review.
Bitwild's subject-named tree is not self-inferrable, so an agent that skips its skill will
confidently create `decisions/`.

### 4. Validate the bundle

```bash
wayfinder validate knowledge
# Machine-readable output:
wayfinder validate knowledge --output json
# Write okf's generated indexes first, then validate:
wayfinder validate knowledge --fix
# SARIF 2.1.0 for code scanning:
wayfinder validate knowledge --output sarif > wayfinder.sarif
```

The command requires exactly one explicit bundle directory and inspects only that
directory. It runs the independent OKF check and every rule of the Profile chain
the project's `wayfinder.json` selects, then derives one gate. Exit `0` (`PASS`)
means OKF passed, no Profile finding is an error, and every selected rule ran;
advisories remain non-blocking. Exit `1` (`FAIL`) means OKF or a Profile rule
failed. Exit `2` (`INCOMPLETE`) means the run could not assess
everything, for example a missing `wayfinder.json`, an unresolved or
unsupported Profile, a link graph
that could not be built, or a usage or I/O error. A `wayfinder/` diagnostic in
the output names the reason.

A `PASS` is conformance to the selected Profile. It is not a review of the
judgment that Profile's skill asks for, such as whether a placement fits its
subject or a source is truthful. The `author-knowledge-bundle` skill runs that
review with each Profile's skill. One `wayfinder validate <bundle>` invocation is the
single supported CI gate. A separate upstream `okf validate` invocation
is optional when focused OKF diagnostics are useful.

## Search local knowledge with Wayfinder

After installing the native runtime, try the illustrative bundle from a clone
of this repository:

```bash
wayfinder get examples/bitwild
wayfinder validate examples/bitwild/knowledge
wayfinder graph examples/bitwild/knowledge --output mermaid
wayfinder index examples/bitwild/knowledge
wayfinder search examples/bitwild/knowledge "How is reporting implemented?"
```

`get` resolves the project's Profile source into `wayfinder.lock`, because
`validate` never fetches. Without it, validation reports
`wayfinder/profile-unresolved` and gate `INCOMPLETE`.

`index` generates and saves document embeddings locally; `search` reuses them
and encodes only the query. There is no retrieval-mode flag. See the
[Wayfinder guide](packages/wayfinder_cli/README.md) for setup, packaging and local data
locations. Existing `okfp validate` remains supported.

`wayfinder mcp <bundle>` exposes the same validation, index, search and graph
services to local MCP hosts over stdio. See the [MCP setup](packages/wayfinder_cli/README.md#mcp-server)
for the launch configuration and tool lifecycle.

## Examples

[`examples/bitwild/`](examples/bitwild/) is a complete project, small enough to read in one
sitting: a `wayfinder.json` binding and a `knowledge/` bundle. It shows Bitwild's central
separations: a source event produces durable knowledge, which links to an execution record,
with generated indexes and an authored log. CI resolves its Profile source from a synthetic
local Git repository. A minimal configured validator fixture is
[`packages/wayfinder/test/fixtures/configured-project/`](packages/wayfinder/test/fixtures/configured-project/).

It includes a two-concept subject area to show that truthful placement, not a
numeric threshold, determines structure.

[`examples/profiles/two-rule/`](examples/profiles/two-rule/) is a complete Profile with two
rules and no parent, and [`examples/acme-notes/`](examples/acme-notes/) is a project that uses
it. [`examples/profiles/two-rule-child/`](examples/profiles/two-rule-child/) builds on Bitwild:
its package names `profiles/bitwild` as its parent at the same commit, so a project names only
the child. CI resolves both from a synthetic local Git repository.

## Reading order

- Adopting a Profile in a project → [Getting started](#getting-started), then the
  [engine contract](implementation/okf-implementation-guide.md) §2
- Writing or editing a concept → the `author-knowledge-bundle` skill, which loads each
  Profile's skill and carries the pinned OKF 0.2 text
- Writing a Profile → the `create-profile` skill, then the engine contract §5
- Building tooling → the engine contract §3 (index generation) and §4 (validation)
- Converting an existing `docs/` tree → the selected Profile's guidance, such as Bitwild's
  [migration reference](profiles/bitwild/skill/references/migration.md)
- Proposing a change → [Contributing](#contributing) below

## Contributing

Changes come in two kinds, and [`AGENTS.md`](AGENTS.md) lists what each needs.

- **The engine contract** says what any Profile package is and how the engine reads it.
  It changes through an ADR and the guide's change record, and a change that would make an
  existing package read differently bumps the package `format`.
- **A Profile** changes through its own release process. A Bitwild rule earns its way in
  by being needed on a real corpus and by being generic. If it names a client, a domain, or
  a project's own vocabulary, it belongs in that project's binding or bundle. Each change
  has a [changelog](profiles/bitwild/CHANGELOG.md) entry stating the **driver** and the
  migration impact.

The driver is the part that does the work. A change record without one is a preference
dressed as a rule, and nobody can tell them apart later.

Two rules govern every Profile edit. **Silence is deference.** Where a Profile says nothing
and OKF settles the point, follow OKF and do not mint a convention in its place. **Precedence
is a chain.** OKF wins over the engine contract, which wins over each Profile package.

## Contributor checks

From the repository root, the core checks used by [CI](.github/workflows/ci.yml) are:

```bash
dart pub get
dart format --output=none --set-exit-if-changed packages/wayfinder/lib packages/wayfinder/test
dart analyze --fatal-infos
(cd packages/wayfinder && dart test)
dart run tool/generate_published_schemas.dart --check
python3 tool/ci/verify-configured-example.py
python3 tool/ci/verify-independent-profile.py
```

`melos lint` runs analysis, formatting and tests across all three packages at once.

The engine embeds no Profile. It embeds only the two published schemas,
`docs/schemas/wayfinder.schema.json` and `docs/schemas/wayfinder-profile.schema.json`, and the
okf package version, through the generated
`packages/wayfinder/lib/src/generated/published_schemas.g.dart`. The version comes from the
`okf:` constraint in `packages/wayfinder/pubspec.yaml`, which allows exactly one patch release
(`'>=0.5.0 <0.5.1'`; every package uses the same constraint), so the embedded value and the
resolved dependency cannot drift. pub rejects a bare version for a published package. After editing either schema or
changing the okf pin, run `dart run tool/generate_published_schemas.dart` and commit the result;
`--check` is the CI gate for a stale file.

Every Profile, Bitwild included, is a package under `profiles/<name>/` that a project fetches
through `wayfinder get`, so editing a package needs no regeneration. A package's shape is
`docs/schemas/wayfinder-profile.schema.json`. The engine runs every schema rule's `tests` when
it parses the package, so a rule whose examples disagree with its check never loads.
`profile_package_test.dart` and `profile_descriptors_test.dart` cover that boundary.

`packages/wayfinder/test/golden_test.dart` pins every fixture's full validation result in
`packages/wayfinder/test/goldens/`. When a change is meant to alter findings, regenerate them
from `packages/wayfinder` with `UPDATE_GOLDENS=1 dart test test/golden_test.dart` and review
the golden diff with the change. An unexpected golden diff is a regression.

**Format with a `stable` SDK, not with the declared floor.** `dart format`'s output is
version-dependent and its style is gated on the package's language version, so a floor
SDK and a newer stable can disagree on the same file. CI checks formatting on `stable`
only — that is what defines the canonical style — while the floor job still analyzes and
tests. Formatting with the floor SDK can produce output CI rejects.

For skill or documentation changes, also check local links and compare changed
rule wording with its authoritative source. Release-tool changes additionally
use the checks under `tool/release/` in CI. Example-gate success covers the
Profile's rules; the judgment its skill asks for is reviewed separately.

See the [release guide](docs/releasing.md) for package publication and native binaries.

## Dart workspace development

Developing the workspace requires Dart 3.11.0 or later. Run `melos get` at the
repository root, then `melos lint` to analyze, check formatting, and test all workspace
packages. Every package declares the same Dart 3.11.0 minimum, matching
`btwld/mix`, so one SDK serves the whole workspace.

`wayfinder_embeddings` moved here from Orbit with its tests, fixtures, and BSD
license preserved in the package directory. See its [README](packages/wayfinder_embeddings/README.md)
and the [retrieval documentation guide](docs/wayfinder_embeddings.md) for the
implementation, evaluation runbook and recorded decisions. Its optional native
backend needs `melos run objectbox:install`; regenerate its committed ObjectBox
files with `melos build` only when entity schemas change.

For native semantic retrieval, `melos run wayfinder_embeddings:prepare` stages the pinned
25.28 MB model. `melos run wayfinder_embeddings:build` creates a
CLI bundle containing the model and native libraries. See the
[local search implementation and measurements](docs/wayfinder_embeddings_local_search.md).
The accepted model choice and next retrieval experiments are recorded in
[ADR-0009](docs/adr/0009-local-knowledge-retrieval.md). `wayfinder validate` provides
bundle validation; search examples and evaluation commands live in the
[embedding package](packages/wayfinder_embeddings/README.md#command-line-entry-points).
