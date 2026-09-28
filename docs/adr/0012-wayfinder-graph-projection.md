# ADR-0012: Wayfinder projects the ordinary OKF graph

- Status: accepted
- Date: 2026-09-11
- Scope: graph projection command and MCP tool; no profile rule changes
- Builds on [ADR-0010](0010-station-cli.md) and [ADR-0011](0011-station-mcp.md)

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
- A live projection of the ordinary OKF graph was selected; it remains
  discardable and read-only.

## Consequences

Agents can inspect the same OKF graph through Wayfinder without a second
server or graph model. The graph remains a discardable projection, not a
source of truth.

## Reconsider when

Reopen this decision if the upstream graph contract changes or a concrete
consumer requires graph semantics that ordinary OKF cannot represent. Such a
change would need a new compatibility review rather than a local graph type.
