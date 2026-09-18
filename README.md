# Wayfinder

Find, connect, and use your project's knowledge. Wayfinder provides local OKF
validation, persistent semantic search, and an MCP server for coding agents.

Source code, plugin files, documentation and binary releases live together in
this public repository. Install the complete native runtime to use Wayfinder
without a Dart SDK. On macOS Apple Silicon or Linux x64:

```sh
curl -fsSL https://raw.githubusercontent.com/conceptadev/wayfinder/main/tool/install.sh | sh
```

On Windows x64, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/conceptadev/wayfinder/main/tool/install.ps1 | iex
```

The [installation guide](docs/install.md) covers plugin setup,
upgrades and troubleshooting.
[GitHub releases](https://github.com/conceptadev/wayfinder/releases) contain the
complete runtime bundles; the [Dart package guide](packages/wayfinder_cli/README.md)
covers library dependencies and source development.

## How it works

Point Wayfinder at an explicit OKF bundle in your project:

```sh
wayfinder validate knowledge
wayfinder index knowledge
wayfinder search knowledge "How is reporting implemented?"
```

Validation checks OKF and the automated rules of the declared Profile. Indexing reads
its documents, computes embeddings locally and saves a local search index.
Search reuses that index and embeds only the query, returning passages with
source paths and line ranges. Run `index` again after editing the bundle;
unchanged content reuses its vectors. The complete installation includes the
model and native libraries, so retrieval needs no external embedding service.

`wayfinder mcp knowledge` exposes `validate`, `index`, `search` and `graph` to
coding agents. The Claude Code plugin configures this server and supplies the
author, adopt and assess skills. `wayfinder validate` provides Profile
validation; `wayfinder graph` projects the ordinary OKF relationship graph
(JSON, or Mermaid/DOT text for an external preview). `wayfinder_embeddings` is
the reusable Dart retrieval library. Upstream `okf` write and concept-authoring
tools remain separate capabilities.

## Concepta OKF Profile

Wayfinder also hosts the **Concepta OKF Profile** — conventions for keeping durable project
knowledge as an [Open Knowledge Format][okf] bundle, together with the skills,
tooling, and examples that put it to work in Concepta repositories.

The aim is a shared project memory, or **second brain**, that people and agents can
read, connect, and use. A bundle can live alongside project code or in a dedicated
knowledge repository. Evidence grounds the knowledge; reusable guidance helps turn
it into work and artifacts. Capture pipelines, artifact templates, and export
automation are workflows to develop around that memory; this repository currently
ships authoring skills and validation, not those production workflows.

The profile is a *profile*, not a format. It defines no file type, no frontmatter field, and
no metadata semantics of its own; every mechanism it uses is defined by OKF and used with its
OKF meaning. OKF is authoritative — where the two appear to differ, OKF wins and the profile
is in error.

Current release: **2026.2**, profiling **OKF 0.2 exactly**. Status: Proposed.
Its canonical text is [`profile/okf-profile.md`](profile/okf-profile.md).

[okf]: https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing

## The dividing line

Everything in this repository is **company-generic**: it holds *how Concepta works*.

A project's `knowledge/` bundle holds *what we know about that project* — its domain, its
decisions, its open questions. Nothing here is ever a prerequisite for reading one. A bundle
must stay readable on its own when a client receives only their project repository, so the
profile is referenced by version, never copied in.

That is why this repository is consumed rather than vendored: install the skills once, pin
the `wayfinder validate` gate, and let each project repository carry only its own knowledge.

## Dart package migration

The `wayfinder` package is now the core validation library (formerly
`okf_profile`). Install `wayfinder_cli` for the `wayfinder` command and MCP server.
The embeddings library remains `wayfinder_embeddings`. All three packages are
published: core 0.1.0, CLI and embeddings 0.1.1. The next prepared application
patch is 0.1.2; see [release status and upgrade notes](docs/releasing.md#prepared-release-012).
See [migration instructions](docs/install.md#migrate-the-dart-application-package).

## What is in here

| Path | Holds |
| --- | --- |
| [`profile/`](profile/) | The normative profile text — the standard itself |
| [`implementation/`](implementation/) | The companion implementation guide: adoption, index generation, validation, migration, distribution |
| [`skills/`](skills/) | The agent skill family — author, adopt, assess, and search a Profiled Bundle, shipped as the `wayfinder` plugin |
| [`packages/wayfinder_cli/`](packages/wayfinder_cli/) | Local CLI and MCP server for validation, graph projection, persistent embedding indexes and semantic search |
| [`packages/wayfinder_embeddings/`](packages/wayfinder_embeddings/) | Chunking, BM25 and dense retrieval utilities, with memory and optional ObjectBox storage |
| [`examples/`](examples/) | A complete worked bundle you can read end to end |
| [`packages/wayfinder/`](packages/wayfinder/) | Core validation library and its tests |
| [`tool/`](tool/) | CI and release tooling |
| [`docs/`](docs/index.md) | Glossary, architecture decisions, compatibility evidence, and maintenance reviews |
| [`AGENTS.md`](AGENTS.md) | Instructions for contributing to this repository |

`profile/okf-profile.md` is the canonical release-integration path; its version
and publication status are declared at the top, never in the filename. During a
release integration it may therefore contain an explicitly unpublished draft
while the current release remains immutable under `profile/versions/`. When the
integration is published, the canonical path again names the current release.
That applies the profile's own §8.1 rule — version and status are metadata and do
not belong in an identity — without silently replacing an identified release.

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
/plugin marketplace add conceptadev/wayfinder
/plugin install wayfinder@wayfinder
```

For an existing installation, follow the [plugin migration sequence](docs/install.md#migrate-an-existing-plugin-installation): uninstall the old plugin and remove its marketplace registration before adding the public repository. This leaves one enabled skill family and MCP server.

Copying or symlinking the skill directories into `~/.claude/skills/` also works — install
all four as a unit, since they reference each other by sibling path. Symlinking is the
better fallback: the skills are versioned with the profile they describe, and a copy
silently ages past it. See [skills/README.md](skills/README.md) for the full set and what
each one does.

### 2. Set up a project repository

In the repository you want to adopt the profile, run:

```
/adopt-knowledge-bundle
```

It is prompt-driven: it explores what the repository already has and applies the
requested setup, asking when an unresolved choice or conflict needs your input.
It preserves existing bundles and seeds a new bundle's root files under `knowledge/` —
the four the profile requires, plus `actors.md` because the seed templates use actor
metadata — and writes the `AGENTS.md` blocks that point agents into the bundle.
It then runs automated validation and Profile Review, reporting any unavailable
check before claiming completion. Issue-tracker and triage-label setup are out of
its scope.

**It creates no directories under `knowledge/`, and that is correct.** A directory
names a *subject*, and generic setup has no corpus from which to judge one (profile
§3.1). A repository whose `knowledge/` is only its root files is fully set up, not
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

You do not need to invoke `author-knowledge-bundle` yourself. It is model-invoked so
authoring mechanics are loaded before a bundle write and contextual rules are loaded for
Profile Review. A subject-named tree is not self-inferrable, so an agent that skips the
profile will confidently create `decisions/`.

### 4. Validate the bundle

```bash
wayfinder validate knowledge
# Machine-readable output:
wayfinder validate knowledge --output json
```

The command requires exactly one explicit bundle directory and inspects only that
directory. It runs the independent OKF check and every deterministic rule selected
by the bundle's Profile declaration. Exit `0` means those automated checks passed;
advisories remain non-blocking. Exit `1` means OKF or deterministic Profile
validation failed, and exit `2` reports usage, I/O, or an unsupported Profile
release.

Automated success is not complete Profile conformance. The output keeps Judgment
Rules explicitly `UNASSESSED`; contextual rules such as subject placement,
metadata truth, and source or relationship meaning require the Profile Review in
the canonical `author-knowledge-bundle` skill. One `wayfinder validate <bundle>` invocation is the
single supported automated CI gate. A separate upstream `okf validate` invocation
is optional when focused OKF diagnostics are useful.

## Search local knowledge with Wayfinder

After installing the native runtime, try the illustrative bundle from a clone
of this repository:

```bash
wayfinder validate examples/knowledge
wayfinder graph examples/knowledge --output mermaid
wayfinder index examples/knowledge
wayfinder search examples/knowledge "How is reporting implemented?"
```

`index` generates and saves document embeddings locally; `search` reuses them
and encodes only the query. There is no retrieval-mode flag. See the
[Wayfinder guide](packages/wayfinder_cli/README.md) for setup, packaging and local data
locations. Existing `okfp validate` remains supported.

`wayfinder mcp <bundle>` exposes the same validation, index, search and graph
services to local MCP hosts over stdio. See the [MCP setup](packages/wayfinder_cli/README.md#mcp-server)
for the launch configuration and tool lifecycle.

## Examples

[`examples/knowledge/`](examples/knowledge/) is a complete bundle, small enough to read in one
sitting, showing the profile's central separations: a source event produces durable knowledge,
which links to an execution record, with generated indexes and an authored log.

It includes a two-concept subject area to show that truthful placement, not a
numeric threshold, determines structure.

## Reading order

- Adopting the profile in a project → [Getting started](#getting-started), then [`implementation/`](implementation/) §2
- Writing or editing a concept → the `author-knowledge-bundle` skill; it delegates to
  [`profile/`](profile/) and carries the pinned OKF 0.2 text alongside it
- Building tooling → [`implementation/`](implementation/) §3 (index generation) and §4 (validation)
- Converting an existing `docs/` tree → [`implementation/`](implementation/) §5 (migration)
- Proposing a change to the profile → [Contributing](#contributing) below

## Contributing

Profile releases are driven by evidence, not by preference. A convention earns its way in by
being needed on a real corpus and by being *generic* — if it names a client, a domain, or a
project's own vocabulary, it belongs in that project's bundle, not here.

The loop:

1. Use the profile on a real project.
2. Open an issue for what it revealed — the case that broke, the rule that had to be decided
   locally, the convention two projects invented separately.
3. Where that justifies a convention, propose it against `profile/`, with its own row in the
   change record (profile §15.3) stating the **driver** and the migration impact.

The driver is the part that does the work. A change record row without one is a preference
wearing a rule's clothes, and the profile has no way to tell them apart later.

Two rules govern the edit itself. **Silence is deference**: where the profile says nothing and
OKF settles the point, follow OKF and do not mint a Concepta convention in its place — that is
the failure mode the profile is least able to detect, because a locally invented rule looks
like a convention rather than a divergence. And **precedence is a chain**: OKF wins over the
profile, which wins over the implementation guide.

## Profile or guide?

Two normative documents, and the difference is *what conforms to each*:

- The **profile** is normative on **bundles**. A bundle either conforms or it does not.
  "A project directory MUST name the subject its concepts genuinely share" belongs here.
- The **implementation guide** is normative on **implementations** — tools, adoptions,
  migrations. "A generator MUST be idempotent" constrains a program, never a bundle, which is
  why it could not have been written in the profile.

Both carry RFC 2119 force; neither is the soft one. The test for a new rule: does it describe
the bundle, or someone acting on the bundle?

## Contributor checks

From the repository root, the core checks used by [CI](.github/workflows/ci.yml) are:

```bash
dart pub get
dart format --output=none --set-exit-if-changed packages/wayfinder/lib packages/wayfinder/test
dart analyze --fatal-infos
(cd packages/wayfinder && dart test)
dart run wayfinder_cli:wayfinder validate examples/knowledge
```

`melos lint` runs analysis, formatting and tests across all three packages at once.

**Format with a `stable` SDK, not with the declared floor.** `dart format`'s output is
version-dependent and its style is gated on the package's language version, so a floor
SDK and a newer stable can disagree on the same file. CI checks formatting on `stable`
only — that is what defines the canonical style — while the floor job still analyzes and
tests. Formatting with the floor SDK can produce output CI rejects.

For skill or documentation changes, also check local links and compare changed
rule wording with its authoritative source. Release-tool changes additionally
use the checks under `tool/release/` in CI. Example-gate success covers automated
checks only; contextual Profile Review remains separate.

## Still owed

- **The index generator** (guide §3). The profile defines deterministic semantic
  membership, grouping, ordering, labels, links, and descriptions. Until a
  generator exists, indexes are hand-maintained and validation catches drift
  (guide §3.4).

See the [maintenance review](docs/maintenance-review.md) for the existing issues
and the remaining project-knowledge workflow questions. See the
[release guide](docs/releasing.md) for package publication and native binaries.

## Dart workspace development

Developing the workspace requires Dart 3.11.0 or later. Run `melos get` at the
repository root, then `melos lint` to analyze, check formatting, and test all workspace
packages. Every package declares the same Dart 3.11.0 minimum, matching
`conceptadev/mix`, so one SDK serves the whole workspace.

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
