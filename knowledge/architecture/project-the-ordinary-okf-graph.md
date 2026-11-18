---
type: Architecture Decision Record
title: Project the ordinary OKF graph
description: The graph is OKF's own, with typed relationship edges beside it, projected in the project library and never a source of truth.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: adr-0012
    title: "ADR-0012: Project the ordinary OKF graph"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#project-the-ordinary-okf-graph-adr-0012-adr-0021
  - id: adr-0021
    title: "ADR-0021: Keep the graph projection in the project library"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#project-the-ordinary-okf-graph-adr-0012-adr-0021
---

# Decision

Project the ordinary OKF graph and add typed relationships beside it, avoiding a competing graph model while exposing the loaded graph to CLI/MCP and embedded hosts.
The projection and `wayfinderLinkFields` live in the project library, with Profile-agnostic field-list injection into graph/retrieval; this graph is discardable, and consumers needing different semantics must seek a compatibility review rather than treating it as a new source of truth.
[Graph output](../../packages/wayfinder_cli/README.md) remains okf JSON/Mermaid/DOT plus relationship edges.
