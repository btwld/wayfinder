# Wayfinder

Find, validate and use your project's knowledge with local search and an MCP
server for coding agents. This repository distributes Wayfinder's native runtime,
installation scripts and the Concepta OKF Profile skill family.

This is a generated distribution from `{{SOURCE_REPO}}` at **{{TAG}}**. It contains
no private source history. Use this repository's issues for installation problems.

## 1. Install the skills

First follow the [installation guide](docs/install.md) to install the complete
Wayfinder runtime and `okfp` validation command. Then, from a project containing
`knowledge/`, run in Claude Code:

```text
/plugin marketplace add conceptadev/wayfinder-dist
/plugin install wayfinder@wayfinder
```

The plugin installs its author, adopt and assess skills together and registers
Wayfinder's `validate`, `index` and `search` MCP tools. It does not configure
upstream OKF graph/write tools; those remain separate capabilities.

## Native releases

Download the complete archive for your platform from
[releases](https://github.com/conceptadev/wayfinder-dist/releases), or use the
installer in the guide. Copying just the executable omits required libraries and
the embedding model. Archives include SHA-256 checksums and dependency notices.

## Dart packages

- [wayfinder](https://pub.dev/packages/wayfinder): CLI and MCP application.
- [wayfinder_embeddings](https://pub.dev/packages/wayfinder_embeddings): reusable retrieval library.
- [okf_profile](https://pub.dev/packages/okf_profile): the `okfp` validation gate.

The source repository remains private. This public projection is regenerated;
changes to generated files must be made in the source and released again.
