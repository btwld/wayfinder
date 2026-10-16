# Documentation index

## Vocabulary

[Glossary](GLOSSARY.md) — Canonical language for Profile packages, validation results, diagnostics, and the gate.

## Compatibility

[Compatibility review](compatibility-review.md) — Evidence that the engine keeps its `okf` package and the pinned OKF 0.2 specification intact.

## Profiles

[Bitwild Profile](../profiles/bitwild/README.md) — The first Profile package: its purpose, one section per rule, and its [changelog](../profiles/bitwild/CHANGELOG.md).

[`acme-notes`](../examples/profiles/two-rule/README.md) is a Profile with two rules and no parent, and [`examples/acme-notes/`](../examples/acme-notes/) is a project that uses it. Neither depends on Bitwild.

## Configuration guides

[Wayfinder project configuration](wayfinder-configuration.md) — Direct-source project bindings, package schemas, explicit lock resolution, and read-only validation order.

## Decisions

[ADR catalog](adr/README.md) — Why the engine, CLI, MCP server, and retrieval are shaped as they are.

## Retrieval evidence

[Retrieval fixtures and benchmarks](../packages/wayfinder_embeddings/fixtures/README.md) — Judged queries, recorded results, and links to the protocols behind them. [ADR-0009](adr/0009-local-knowledge-retrieval.md) records the model choice they support.

## Operations

[Install Wayfinder](install.md) — Native installation without Dart, plugin setup and migration, usage, upgrades and troubleshooting.

[Contribute to Wayfinder](contributing.md) — Change requirements, contributor checks, schema generation, goldens, and native development.

[Release Wayfinder](releasing.md) — Package tags, pub.dev OIDC, verified native bundles and cli_pkg/Grinder tasks.
