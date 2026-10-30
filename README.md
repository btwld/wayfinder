# Wayfinder

Wayfinder validates and searches project knowledge kept beside code.

## Core concepts

- **A bundle is portable Markdown:** concepts with [OKF](skills/author-knowledge-bundle/references/OKF-0.2.md) YAML metadata, indexes and a log.
- **Authority runs OKF → engine contract → Profile.** Profiles add team rules without redefining OKF. Bitwild is optional; no Profile is a required base.
- **Configuration selects; the lock pins.** `wayfinder.json` chooses the Profile source, `get` pins its Git revision, and validation uses the local lock/cache without fetching.
- **Validation is conformance:** `PASS` (exit 0), `FAIL` (1), or `INCOMPLETE` (2). It does not establish truth, relevance or sound judgment.
- **Search is local and explicitly indexed.** It returns cited evidence, not answers. During refresh it can return the previous snapshot with notices; verify changed sources before relying on them.
- **Source files are authoritative.** Search indexes and graph views are derived and rebuildable.
- **Skills separate mechanics from conventions.** Generic skills handle OKF and Wayfinder; each Profile's skill carries its judgment.
- **Libraries power CLI and MCP.** Public Dart APIs support embedding. Project knowledge belongs in the project's bundle; this repository holds reusable tools, Profiles and illustrative examples.

## Install

On macOS Apple Silicon or Linux x64:

```sh
curl -fsSL https://raw.githubusercontent.com/btwld/wayfinder/main/tool/install.sh | sh
```

For Windows PowerShell, upgrades, plugin setup and troubleshooting, see the
[installation guide](docs/install.md). Native bundles include the local model
and libraries; no Dart SDK or external embedding service is needed.

## Getting started

In a project with a configured `knowledge/` bundle:

```sh
wayfinder get .
wayfinder validate knowledge
wayfinder index knowledge
wayfinder search knowledge "How is reporting implemented?"
wayfinder graph knowledge --output mermaid
```

Reindex after edits; unchanged content reuses vectors. Search never implicitly
rebuilds an index. Without a path, `wayfinder index` and
`wayfinder search "your question"` use all configured project bundles.
Use `validate --output json` or `--output sarif` for automation; `--fix` repairs
stale generated indexes when the selected Profile requires them.

For a new bundle, invoke `/adopt-knowledge-bundle`; it preserves existing bundles
and asks which Profile to use. [Bitwild](profiles/bitwild/README.md) is one option;
[`create-profile`](skills/create-profile/SKILL.md) and the
[two-rule example](examples/profiles/two-rule/README.md) support independent rules.

### Try an example

This repository has no root `knowledge/`. In a clone, substitute
`examples/bitwild` for the `get` path and `examples/bitwild/knowledge` for the
bundle path in the commands above. See [examples](examples/README.md).

## Use with coding agents

Install the [skill family](skills/README.md) together. Authoring and retrieval
load as needed; adoption, assessment and Profile creation are explicitly invoked.
`wayfinder get` installs each Profile's skill into the project, pinned to its lock;
commit those skill directories with the lock.

Run `wayfinder setup` to configure project MCP. `wayfinder mcp` serves
`validate`, `index`, `search` and `graph` across configured bundles over stdio;
`wayfinder mcp <bundle>` selects one. See the
[MCP guide](packages/wayfinder_cli/README.md#mcp-server).

## Documentation

| Need | Start here |
| --- | --- |
| Install or configure | [Install](docs/install.md), [project configuration](docs/wayfinder-configuration.md) |
| Author, review or adopt knowledge | [Skills](skills/README.md), [examples](examples/README.md) |
| Embed or understand the engine | [API routes](docs/index.md#cli-mcp-and-dart-apis), [contract](implementation/README.md), [decisions](docs/adr/README.md) |
| Develop or release | [Contributing](docs/contributing.md), [releasing](docs/releasing.md) |

## Repository layout

`packages/` holds core validation/projects, CLI/MCP, embeddings and Dart chunking.
`profiles/bitwild/` owns Bitwild's rules, skill and history; `skills/` is generic.
`implementation/` and `docs/schemas/` hold the engine contract. `examples/` holds
illustrative bundles; `docs/` holds guides and decisions; `tool/` holds tooling.

## Contributing

Read [AGENTS.md](AGENTS.md) and the [change requirements](docs/contributing.md).

## Contributor checks

Run the [core checks](docs/contributing.md#checks) and report results.
Development requires Dart 3.11 or later; stable SDK formatting is canonical.
