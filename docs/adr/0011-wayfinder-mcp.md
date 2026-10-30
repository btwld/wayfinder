# ADR-0011: Serve Wayfinder tools over local MCP stdio

- Status: accepted
- Date: 2026-09-09
- Updated: 2026-10-16 (project discovery); 2026-10-20 (encoder, cache and Markdown output)
- Scope: local MCP adapter; no Profile rule
- Builds on: [ADR-0010](0010-wayfinder-cli.md)
- Amended by: [ADR-0022](0022-plain-file-index-generations.md) (search during refresh)

## Context and decision

Agents need validation and cited retrieval without parsing shell output or
implementing another search. Expose `validate`, `index`, `search`, and read-only
`graph` through `wayfinder mcp`, a local stdio server over the same libraries as
the CLI. Upstream `okf mcp` supplies format operations, not Wayfinder's gate.
Shell-only access lacks typed tool discovery; HTTP hosting is deferred until a
real deployment needs authentication or remote access.

Discover configured project bundles on each call without fetching; fall back to
`knowledge/`. Explicit `wayfinder mcp <bundle>` or `WAYFINDER_KNOWLEDGE_DIR`
binds one bundle. Tool arguments cannot choose arbitrary paths. Project search
uses one query embedding, a global limit and bundle-aware citations; validation
and graph remain independent per bundle. Missing/incompatible indexes fail;
ADR-0022 permits previous snapshots during refresh with notices.

Use the MCP SDK for framing and Ack for arguments. Stdout is JSON-RPC only;
diagnostics use stderr. Validation, index and graph return JSON text; search
returns Markdown candidates and notices. Failing validation findings are completed
results with an exit code; execution errors use `isError` without ending the
session. See the [MCP guide](../../packages/wayfinder_cli/README.md#mcp-server).

## Consequences

There is one validation/retrieval contract, no authoring tool or answer-confidence
claim. Indexing writes derived local data explicitly; host approval controls it.
MCP shares a lazy encoder and bounded snapshot cache. Cancellation stops searches,
not an index already building; per-bundle publication is not a multi-bundle
transaction. A later bundle's index failure leaves earlier publications intact.
