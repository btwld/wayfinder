---
type: Architecture Decision Record
title: Serve MCP over the CLI's services
description: Validate, index, search, query and graph over local MCP stdio on the CLI's own services, with no HTTP, authentication or authoring tool.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: adr-0011
    title: "ADR-0011: Serve Wayfinder tools over local MCP stdio"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#local-mcp-over-shared-services-adr-0011
---

# Decision

Expose validate/index/search/query/graph over local MCP stdio using the CLI's services, because agents need typed discovery/results without implementing another gate or search; default discovery spans project bundles, with an explicit single-bundle override.
Deferring HTTP/authentication and authoring tools keeps the boundary small, but hosts own approval and lifecycle, and per-bundle indexing cannot roll back an earlier publication when a later bundle fails.
[Transport and cancellation details](../../packages/wayfinder_cli/README.md#mcp-server) remain operational guidance; [Keep indexes as plain-file generations](../retrieval/publish-indexes-as-immutable-generations.md) governs refresh reads.
