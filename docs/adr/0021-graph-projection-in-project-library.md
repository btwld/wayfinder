# ADR-0021: Keep the graph projection in the project library

- Status: accepted
- Date: 2026-10-24
- Scope: where the graph projection lives, and which field list it uses; no Profile rule and no change to graph output
- Amends: [ADR-0012](0012-wayfinder-graph-projection.md)
- Builds on [ADR-0018](0018-embeddable-libraries.md)

## Context

[ADR-0012](0012-wayfinder-graph-projection.md) projects the ordinary OKF graph
and adds `relationships` edges beside it. That record named the field list as
a generic `wayfinder_embeddings` seam the CLI configured. The projection then
moved into `package:wayfinder/project.dart` so a host can draw the same graph
without the CLI. Graph output is unchanged. ADR-0012 stays as it was accepted;
this record carries the change.

## Decision

- `projectWayfinderGraph` and its query input live in
  `package:wayfinder/project.dart`. A host uses them directly. The `graph`
  command and the MCP tool stay a shell over that projection.
- The field list is `wayfinderLinkFields`, the engine's `relationships` key.
  `okfFieldEdges` and the retrieval library take that list as a parameter.
  Neither holds Profile knowledge.
- Graph output is unchanged: okf's JSON, Mermaid and DOT, plus one edge per
  `relationships` entry.

## Consequences

A host projects the graph the command projects. ADR-0012 still decides what
that graph is.
