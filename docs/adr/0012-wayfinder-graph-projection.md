# ADR-0012: Project the ordinary OKF graph

- Status: accepted
- Date: 2026-09-11
- Updated: 2026-10-01 (typed `relationships` edges beside the okf graph); 2026-10-22 (the projection moved into `package:wayfinder/project.dart`; output unchanged)
- Scope: the `graph` command and MCP tool; no Profile rule
- Builds on [ADR-0010](0010-wayfinder-cli.md) and [ADR-0011](0011-wayfinder-mcp.md)

## Context

Wayfinder already builds `OkfGraph.fromBundle` for search expansion and link
validation. Upstream `okf graph` emits that object as JSON, Mermaid, or DOT,
but users had to run a second CLI to see it. Typed links live in the
`relationships` frontmatter key, which okf's graph does not read. A separate
Wayfinder graph model could drift from OKF's graph contract.

## Decision

- `wayfinder graph <bundle>` is a live projection of `OkfGraph.fromBundle`.
  It opens neither the search index nor the embedding model.
- It keeps okf's query and output contract: `--output json|mermaid|dot`
  (default `json`), repeatable `--type`, `--path-prefix`, and `--resolution`.
  Mermaid and DOT are text for an external preview.
- Each `relationships` entry is added beside the unchanged okf graph. JSON
  keeps every okf key and adds a `field_edges` array; Mermaid and DOT add one
  edge per entry, labelled with its relationship name. The frontmatter key
  list is `wayfinderLinkFields`, the engine's `relationships` key.
  `okfFieldEdges` and the retrieval library take a field list as a generic
  parameter, so neither holds Profile knowledge.
- The projection, `projectWayfinderGraph`, and its query input are part of
  `package:wayfinder/project.dart` ([ADR-0018](0018-embeddable-libraries.md)),
  so a host projects the same graph without the CLI.
- The graph is refused when `OkfBundleLoader.inspect` has findings, matching
  `okf graph`.
- The same JSON is a read-only MCP `graph` tool whose arguments follow
  `OkfGraphQuery`. Writes and concept authoring stay with upstream `okf`.

## Options considered

- A second graph model was rejected because it could drift from OKF.
- Delegating every graph view to an upstream process was rejected because
  Wayfinder already holds the loaded graph and owns the local MCP boundary.

## Consequences

Agents inspect the same OKF graph through Wayfinder without a second server.
The graph is a discardable projection, never a source of truth.

## Reconsider when

The upstream graph contract changes, or a consumer needs graph semantics
ordinary OKF cannot represent. Such a change needs a compatibility review.
