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

[Architecture decision log](../ARCHITECTURE.md) — Why the engine, CLI, MCP server, and retrieval are shaped as they are.

## Retrieval evidence

[Retrieval fixtures and benchmarks](../packages/wayfinder_embeddings/fixtures/README.md) — Judged queries, recorded results, and links to the protocols behind them. [ADR-0009](adr/0009-local-knowledge-retrieval.md) records the model choice they support.

## Operations

[Install Wayfinder](install.md) — Native installation without Dart, plugin setup and migration, usage, upgrades and troubleshooting.

[Contribute to Wayfinder](contributing.md) — Change requirements, contributor checks, schema generation, goldens, and native development.

[Release Wayfinder](releasing.md) — Package tags, pub.dev OIDC, verified native bundles and cli_pkg/Grinder tasks.

## CLI, MCP, and Dart APIs

| Interface | Use it for | Entry point |
| --- | --- | --- |
| CLI | Terminal workflows and CI, with text or JSON results; validation also supports SARIF. | [`wayfinder`](../packages/wayfinder_cli/README.md) |
| MCP | Agent access to `validate`, `index`, `search`, and `graph` across configured project bundles (or one explicit bundle) over stdio. | [`wayfinder mcp <bundle>`](../packages/wayfinder_cli/README.md#mcp-server) |
| Dart validation | Embed validation and consume typed findings, diagnostics, and gate results. | [`ProfileValidator`](../packages/wayfinder/README.md) from `package:wayfinder/wayfinder.dart` |
| Dart projects | Embed what the CLI does with a project: discover its bundles, resolve and select Profiles, relock an edit of `wayfinder.json` offline, validate, and project the graph. | [`WayfinderProject` and `WayfinderProfileResolver`](../packages/wayfinder/README.md#projects) from `package:wayfinder/project.dart` |
| Dart knowledge store | Embed what `wayfinder index` and `search` do: saved indexes of a project's bundles, status, progress, cancellation, and ranked, cited search that keeps working while an index runs. | [`WayfinderKnowledgeStore`](../packages/wayfinder_embeddings/README.md#knowledge-store) from `package:wayfinder_embeddings/knowledge_store.dart`, with a test encoder in `testing.dart` |
| Dart adoption | Plan and apply a project's adoption of a Profile: binding, lock, Profile skills, and the seeded bundle. | [`KnowledgeAdoption`](../packages/wayfinder/README.md#adoption) from `package:wayfinder/adoption.dart` |
| Dart authoring | Write a bundle a Profile governs: prepare one change, judge the candidate in memory, then commit it or report why not. | [`KnowledgeWriter`](../packages/wayfinder/README.md#authoring) from `package:wayfinder/authoring.dart` |
| Dart retrieval | Build custom chunking and search workflows, including an OKF adapter. | [`wayfinder_embeddings`](../packages/wayfinder_embeddings/README.md), with `KnowledgeSnapshot` and `KnowledgeIndex` in `okf_knowledge.dart` and model provisioning with [`EmbeddingModelCache`](../packages/wayfinder_embeddings/README.md#provision-the-model-from-an-application) in `model_cache.dart`; Dart source chunking in [`wayfinder_dart_chunker`](../packages/wayfinder_dart_chunker/README.md) |

CLI and MCP search can span configured bundles. CLI search also supports
[frontmatter filters](../packages/wayfinder_cli/README.md#filter-search-by-frontmatter).
MCP search accepts only `query` and an optional `limit`. Search is dense-only
and requires the verified local embedding model. Indexing is explicit in both:
search does not rebuild a missing or stale index. MCP does not expose
concept-authoring writes.

The Dart OKF adapter also requires an embedder; there is no model-free search
fallback. Chunk preview and snapshot parsing remain model-free. See the
[API guide](../packages/wayfinder_embeddings/README.md#search-an-okf-bundle) and
[dense-only migration](../docs/adr/0017-dense-only-retrieval.md).
