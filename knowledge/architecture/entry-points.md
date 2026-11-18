---
type: Architecture Document
title: Entry points
description: "Which interface serves which caller: the CLI, MCP, each public Dart library and the Flutter SDK, with the document that owns each."
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:46:30Z
sources:
  - id: docs-index
    title: Documentation index
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/index.md#cli-mcp-and-dart-apis
---

# CLI, MCP, and Dart APIs

| Interface | Use it for | Entry point |
| --- | --- | --- |
| CLI | Terminal workflows and CI, with text or JSON results; validation also supports SARIF. | [`wayfinder`](../../packages/wayfinder_cli/README.md) |
| MCP | Agent access to `validate`, `index`, `search`, `query`, and `graph` across configured project bundles (or one explicit bundle) over stdio. | [`wayfinder mcp <bundle>`](../../packages/wayfinder_cli/README.md#mcp-server) |
| Dart validation | Embed validation and consume typed findings, diagnostics, and gate results. | [`ProfileValidator`](../../packages/wayfinder/README.md) from `package:wayfinder/wayfinder.dart` |
| Portable knowledge | Retained byte values, snapshots, independent leases, cancellation and the memory backend without native dependencies in the import closure. | [`knowledge.dart`](../../packages/wayfinder/README.md#portable-retained-knowledge) from `package:wayfinder/knowledge.dart` |
| Read-only local knowledge | Bounded filesystem browsing capture without Profile fetching or source writes. | [`LocalKnowledgeProject.open`](../../packages/wayfinder/README.md#read-only-filesystem-loader) from `package:wayfinder/project.dart` |
| Dart projects | Embed what the CLI does with a project: discover its bundles, resolve and select Profiles, relock an edit of `wayfinder.json` offline, validate, and project the graph. | [`WayfinderProject` and `WayfinderProfileResolver`](../../packages/wayfinder/README.md#projects) from `package:wayfinder/project.dart` |
| Dart knowledge store | Embed what `wayfinder index` and `search` do: saved indexes of a project's bundles, status, progress, cancellation, and ranked, cited search that keeps working while an index runs. | [`WayfinderKnowledgeStore`](../../packages/wayfinder_embeddings/README.md#knowledge-store) from `package:wayfinder_embeddings/knowledge_store.dart`, with a test encoder in `testing.dart` |
| Dart adoption | Plan and apply a project's adoption of a Profile: binding, lock, Profile skills, and the seeded bundle. | [`KnowledgeAdoption`](../../packages/wayfinder/README.md#adoption) from `package:wayfinder/adoption.dart` |
| Dart authoring | Write a bundle a Profile governs: prepare one change, judge the candidate in memory, then commit it or report why not. | [`KnowledgeWriter`](../../packages/wayfinder/README.md#authoring) from `package:wayfinder/authoring.dart` |
| Dart retrieval | Build custom chunking and search workflows, including an OKF adapter. | [`wayfinder_embeddings`](../../packages/wayfinder_embeddings/README.md), with `KnowledgeSnapshot` and `KnowledgeIndex` in `okf_knowledge.dart` and model provisioning with [`EmbeddingModelCache`](../../packages/wayfinder_embeddings/README.md#provision-the-model-from-an-application) in `model_cache.dart` |
| Flutter reader SDK | Use portable reader models, graph widgets and file-tree/link helpers; hosts supply backends and state. | [Package README](../../packages/wayfinder_flutter/README.md) and [integration and graph guide](../../packages/wayfinder_flutter/doc/integration.md) |

- [Structured queries and saved views](../../docs/queries.md) — model-free concept selection, grouping, CLI/MCP and project query IDs.

Model-free knowledge: [portable values and memory leases](../../packages/wayfinder/README.md#portable-retained-knowledge)
from `package:wayfinder/knowledge.dart`, [native read-only filesystem loading](../../packages/wayfinder/README.md#read-only-filesystem-loader)
from `package:wayfinder/project.dart`, and
[shared Flutter integration](../../packages/wayfinder_flutter/doc/integration.md).
