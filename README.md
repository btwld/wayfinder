# Wayfinder

Wayfinder helps teams and coding agents find and maintain project knowledge.
Keep decisions, domain concepts, and guides alongside your code in an
[Open Knowledge Format (OKF)][okf] bundle: Markdown files with YAML frontmatter.

- **Find context with citations.** Search in natural language and follow results
  back to source files and line ranges.
- **Check team conventions in CI.** Validate OKF and the rules you choose,
  packaged as a Profile, with one CI gate.
- **Give agents the same knowledge.** Expose the bundle through MCP and use
  skills to author, adopt, and review it.
- **Keep your knowledge portable.** The bundle stays readable as files and by
  other OKF tools, without Wayfinder or a Profile installed.

Indexing and search run locally. The native installation includes the embedding
model and libraries; no Dart SDK or external embedding service is needed.

[okf]: https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing

## Install

On macOS Apple Silicon or Linux x64:

```sh
curl -fsSL https://raw.githubusercontent.com/btwld/wayfinder/main/tool/install.sh | sh
```

On Windows x64, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/btwld/wayfinder/main/tool/install.ps1 | iex
```

The installer includes the runtime and agent skills. See the
[installation guide](docs/install.md) for plugin setup, upgrades, and
troubleshooting, or [GitHub releases](https://github.com/btwld/wayfinder/releases)
for runtime bundles.

## Getting started

In a project with a configured `knowledge/` bundle:

```sh
wayfinder get .
wayfinder validate knowledge
wayfinder index knowledge
wayfinder search knowledge "How is reporting implemented?"
wayfinder graph knowledge --output mermaid
```

`get` resolves the Profile selected in `wayfinder.json` and pins it in
`wayfinder.lock`. Run it before validation: `validate` reads the lock and local
cache, but never fetches a Profile.

`index` saves document embeddings locally. Run it again after editing the bundle;
unchanged content reuses its vectors. `search` reuses the index and embeds only
the query. It returns candidate passages, not generated answers; check the cited
text before using it. For projects with several bundles, `wayfinder index` and
`wayfinder search "your question"` use the configured bundle paths. An explicit
path selects just one bundle.

**Starting a new bundle?** In your coding agent, invoke
`/adopt-knowledge-bundle`. It explores the repository, binds the bundle to a
Profile, seeds the files its adoption guidance calls for, and adds agent
instructions. Existing bundles are preserved. Without Profile-specific seed
guidance, a new bundle starts with only OKF's `index.md` and `log.md`.

### Try an example

From a clone of this repository, use the [Bitwild example](examples/bitwild/):

```sh
wayfinder get examples/bitwild
wayfinder validate examples/bitwild/knowledge
wayfinder index examples/bitwild/knowledge
wayfinder search examples/bitwild/knowledge "How is reporting implemented?"
```

There is no root `knowledge/` directory in this repository. The
[examples guide](examples/README.md) explains the worked bundle and includes a
small independent Profile you can use without Bitwild.

## Use with coding agents

The installer supplies Wayfinder's skills through the Claude Code plugin when
the `claude` CLI is available, or as skill directories otherwise. It also installs
them in `~/.agents/skills` for Codex and other Agent Skills clients.
`wayfinder update` refreshes the skills with the runtime.

To add the MCP server to a project's `.mcp.json`, run:

```sh
wayfinder setup
```

The server exposes `validate`, `index`, `search`, and `graph` across the project's
configured bundles, with a `knowledge/` fallback. Other MCP hosts can launch
`wayfinder mcp` over stdio. Use `wayfinder mcp <bundle>` or set
`WAYFINDER_KNOWLEDGE_DIR` to restrict it to one explicit bundle. See the
[MCP guide](packages/wayfinder_cli/README.md#mcp-server). For manual plugin
installation, follow the
[plugin setup guide](docs/install.md#install-the-claude-code-plugin).

| Skill | Use it to |
| --- | --- |
| `adopt-knowledge-bundle` | Set up a bundle and connect it to a Profile. |
| `author-knowledge-bundle` | Create, edit, move, deprecate, or mirror content, then review it. |
| `assess-knowledge-bundle` | Review the whole bundle using its Profile's guidance. |
| `use-wayfinder` | Search, index, validate, and explore the graph; answer from verified passages. |
| `create-profile` | Create or revise a Profile's rules, tests, and skill. |

Agents load `author-knowledge-bundle` and `use-wayfinder` as needed. You invoke
adoption, assessment, and Profile creation explicitly. Install the
[skill family](skills/README.md) together: the skills reference one another.

A Profile's own skill is separate. `wayfinder get` installs it into the project's
`.claude/skills/<id>/` and `.agents/skills/<id>/`, pinned to the locked commit.
Commit those directories with the lock. See
[Profile skills](docs/wayfinder-configuration.md#profile-skills).

## Profiles

A Profile packages your team's vocabulary and validation rules in
`wayfinder-profile.json`. It can also include a README explaining the rules and
an agent skill for judgment that rules cannot automate.

The project selects a Profile in `wayfinder.json`. Every Profile adds to OKF
without changing what OKF fields mean, and the bundle stays readable by any OKF
tool. A Profile can extend another, but none is a required base or default.

[Bitwild](profiles/bitwild/README.md) is the first Profile. It guides what earns
a concept, where knowledge belongs, and how it links to the systems where work
happens. You can use it, extend it, or write an independent Profile with
`create-profile`. The [two-rule example](examples/profiles/two-rule/README.md)
shows an independent package; the
[engine contract](implementation/okf-implementation-guide.md#5-profile-packages)
defines the package format.

This repository holds reusable tooling, skills, and Profiles. Your project's
domain knowledge, decisions, and open questions belong in its own bundle.
Reference a Profile through configuration and the lock; do not copy this
repository into the bundle.

## CLI, MCP, and Dart APIs

| Interface | Use it for | Entry point |
| --- | --- | --- |
| CLI | Terminal workflows and CI, with text or JSON results; validation also supports SARIF. | [`wayfinder`](packages/wayfinder_cli/README.md) |
| MCP | Agent access to `validate`, `index`, `search`, and `graph` for one bundle over stdio. | [`wayfinder mcp <bundle>`](packages/wayfinder_cli/README.md#mcp-server) |
| Dart validation | Embed validation and consume typed findings, diagnostics, and gate results. | [`ProfileValidator`](packages/wayfinder/README.md) from `package:wayfinder/wayfinder.dart` |
| Dart retrieval | Build custom chunking and search workflows, including an OKF adapter. | [`wayfinder_embeddings`](packages/wayfinder_embeddings/README.md), with `KnowledgeSnapshot` and `KnowledgeIndex` in `okf_knowledge.dart`; Dart source chunking in [`wayfinder_dart_chunker`](packages/wayfinder_dart_chunker/README.md) |

CLI and MCP search can span configured bundles. CLI search also supports
[frontmatter filters](packages/wayfinder_cli/README.md#filter-search-by-frontmatter).
MCP search accepts only `query` and an optional `limit`. Search is dense-only
and requires the verified local embedding model. Indexing is explicit in both:
search does not rebuild a missing or stale index. MCP does not expose
concept-authoring writes.

The Dart OKF adapter also requires an embedder; there is no model-free search
fallback. Chunk preview and snapshot parsing remain model-free. See the
[API guide](packages/wayfinder_embeddings/README.md#search-an-okf-bundle) and
[dense-only migration](docs/adr/0017-dense-only-retrieval.md).

## Validation and CI

Validation requires one explicit bundle directory. It checks OKF first, then
the rules in the selected Profile chain, and returns one gate:

| Exit | Gate | Meaning |
| --- | --- | --- |
| `0` | `PASS` | OKF passed, every selected rule ran, and no Profile finding is an error. Advisories do not block. |
| `1` | `FAIL` | OKF or a Profile rule failed. |
| `2` | `INCOMPLETE` | The run could not assess everything, such as a missing configuration, unresolved Profile, or I/O error. |

Use `wayfinder validate knowledge` as the CI gate. Text is the default output;
JSON and SARIF are also available:

```sh
wayfinder validate knowledge --output json
wayfinder validate knowledge --output sarif > wayfinder.sarif
```

To write OKF's generated indexes when the selected Profile requires them, then
validate, run `wayfinder validate knowledge --fix`.

**A passing gate is conformance, not a content review.** It does not establish
whether a source is truthful or a concept belongs where it was placed. The
authoring and assessment skills use each Profile's skill to review that judgment.
See the [validation contract](implementation/okf-implementation-guide.md#4-validation)
for result details and diagnostics.

## Documentation

| If you want to… | Start here |
| --- | --- |
| Install, upgrade, or troubleshoot | [Installation guide](docs/install.md) |
| Configure a project or change its Profile | [Project configuration](docs/wayfinder-configuration.md) |
| Author or review bundle content | [Agent skills](skills/README.md) |
| Write a Profile | [`create-profile`](skills/create-profile/SKILL.md) and the [engine contract](implementation/okf-implementation-guide.md#5-profile-packages) |
| Explore a worked bundle | [Examples](examples/README.md) |
| Develop or release Wayfinder | [Contributor guide](docs/contributing.md) and [release guide](docs/releasing.md) |

The [documentation index](docs/index.md) also covers vocabulary, compatibility,
architecture decisions, and retrieval evidence.

## Repository layout

| Path | Contents |
| --- | --- |
| [`packages/wayfinder/`](packages/wayfinder/) | Core Dart validation library and tests |
| [`packages/wayfinder_cli/`](packages/wayfinder_cli/) | CLI and MCP server |
| [`packages/wayfinder_embeddings/`](packages/wayfinder_embeddings/) | Reusable local retrieval library |
| [`packages/wayfinder_dart_chunker/`](packages/wayfinder_dart_chunker/) | Dart source chunking for the retrieval library |
| [`profiles/bitwild/`](profiles/bitwild/) | Bitwild's rules, skill, rationale, and releases |
| [`skills/`](skills/) | Profile-agnostic agent skills |
| [`implementation/`](implementation/) | Engine contract |
| [`examples/`](examples/) | Illustrative bundles and Profile packages |
| [`docs/`](docs/index.md) | Guides, schemas, decisions, and compatibility evidence |
| [`tool/`](tool/) | CI and release tooling |

## Contributing

Read [AGENTS.md](AGENTS.md) for scope and change requirements. The authority order
is **OKF → engine contract → Profile package**. Contract changes need an ADR and
change record; Profile changes follow that package's release process and need
evidence from a real corpus.

The [contributor guide](docs/contributing.md) covers schema generation, goldens,
formatting, and native development. Developing the workspace requires Dart
3.11.0 or later; use a stable SDK for formatting.

## Contributor checks

From the repository root, run the core checks used by [CI](.github/workflows/ci.yml):

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages/wayfinder/lib packages/wayfinder/test
dart analyze --fatal-infos
(cd packages/wayfinder && dart test)
dart run tool/generate_published_schemas.dart --check
python3 tool/ci/verify-configured-example.py
python3 tool/ci/verify-independent-profile.py
```

`dart run melos run lint` runs analysis, formatting, and tests across all four
packages. For documentation or skill changes, also check local links and compare
changed rule wording with its authoritative source.
