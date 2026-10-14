# ADR-0012: Wayfinder projects the ordinary OKF graph

- Status: accepted
- Date: 2026-09-11
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0012-wayfinder-graph-projection.md))
- Scope: graph projection command and MCP tool; no Profile rule changes
- Builds on [ADR-0010](0010-wayfinder-cli.md) and [ADR-0011](0011-wayfinder-mcp.md)
- Amended 2026-10-01 for Profile 2026.3: relationships moved to the
  `relationships` frontmatter key ([Profile §7.2](../../profile/okf-profile.md#72-relationships)),
  which okf's graph does not read. `wayfinder graph` and the MCP `graph` tool
  now add each entry beside the unchanged okf graph: JSON gains a
  `field_edges` array, with every okf key and meaning kept, and Mermaid and
  DOT add one edge per entry labelled with its relationship name. The
  frontmatter key list is a generic `wayfinder_embeddings` seam the CLI
  configures, so the library holds no Profile knowledge. This revises the
  "no second graph model" decision below only by these additive edges.

## Context

Wayfinder already builds `OkfGraph.fromBundle` for search expansion and
link validation. Upstream `okf graph` and `okf mcp` `query-graph` emit that
same object as versioned JSON, Mermaid, or DOT. Users still had to run a
second CLI to see the graph. A second graph model would violate Profile §13
and the implementation guide's "ordinary OKF graph without an adapter" rule.

## Decision

- Add `wayfinder graph <bundle>` as a live projection of
  `OkfGraph.fromBundle`. It does not open the search index or embedding
  model.
- Keep okf's query and output contract: `--output json|mermaid|dot`
  (default `json`), repeatable `--type`, `--path-prefix`, and
  `--resolution`. Mermaid and DOT are text for an external preview;
  Wayfinder does not render a picture.
- Refuse a graph when `OkfBundleLoader.inspect` has findings, matching
  `okf graph`.
- Expose the same JSON as a read-only MCP `graph` tool whose arguments
  follow `OkfGraphQuery`. Writes and concept authoring remain upstream
  `okf` tools.

## Options considered

- A second Wayfinder graph model was rejected because it could drift from OKF's
  graph contract.
- Delegating every graph view to a second upstream process was rejected because
  Wayfinder already has the loaded graph and its MCP server owns the local
  service boundary.

## Consequences

Agents can inspect the same OKF graph through Wayfinder without a second
server or graph model. The graph remains a discardable projection, not a
source of truth.

## Reconsider when

Reopen this decision if the upstream graph contract changes or a concrete
consumer requires graph semantics that ordinary OKF cannot represent. Such a
change would need a new compatibility review rather than a local graph type.
