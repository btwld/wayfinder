# ADR-0011: Serve Wayfinder tools over local MCP stdio

- Status: accepted
- Date: 2026-09-09
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0011-station-mcp.md))
- Scope: local MCP adapter; no Profile rule changes
- Builds on [ADR-0010](0010-wayfinder-cli.md)
- Amended 2026-10-16 for project-wide discovery: project knowledge and installed
  reference bundles need one agent search, matching the CLI added in #121.
  Explicit single-bundle launches keep their existing behavior and JSON.

## Context

Agents need Wayfinder validation and retrieval without parsing shell output
or maintaining another search implementation. Upstream `okf mcp` serves
format-level reads and writes; it does not replace Wayfinder's Profile gate
or semantic search.

## Decision

Run `wayfinder mcp` as a local stdio server over the project's configured
bundles, using the same discovery boundary and conventional `knowledge/`
fallback as CLI project search. Discover on each call without fetching sources.
Search uses one query embedding and one global result limit, preserving
bundle-aware citations. Index explicitly refreshes every selected bundle;
a missing or stale index fails search rather than returning a subset.
Validation and graph remain independent per bundle, returned under `bundles`
with each bundle's name and project-relative path. Validation gates and graph
node identities are never merged across bundles.

An explicit `wayfinder mcp <bundle>` stays bound to that canonical bundle at
startup and preserves its original result shapes. A nonblank
`WAYFINDER_KNOWLEDGE_DIR` selects that mode when no argument is supplied. The
plugin and new setup entries default to project mode; migrate existing entries
with `wayfinder setup --force` and restart the host. Tool arguments cannot
select an arbitrary path or retrieval mode. Use the MCP SDK for transport,
negotiation, and framing, and the
published ACK adapter for argument validation and defaults. Stdout carries
JSON-RPC only; diagnostics use stderr. Keep dependency versions in the
[package manifest](../../packages/wayfinder_cli/pubspec.yaml), not this ADR.

Expose the existing Wayfinder `validate`, `index`, and `search` services.
[ADR-0012](0012-wayfinder-graph-projection.md) adds read-only `graph`.
Return each result once as JSON in one text content block. Validation
findings are a completed report with an `exit_code`, not a failed tool call;
execution failures use `isError` without ending the session. Search returns
candidate passages, citations, and notices, not an answer-confidence claim.

Discovery and validation need no model. Indexing is explicit and writes only
derived app data; search refuses stale indexes. Tool annotations identify
read-only calls and non-destructive indexing, while the host controls
approval. No HTTP host, authentication service, or bundle-authoring tool is
introduced here.

Each retrieval call owns and disposes its model and store. Overlapping calls
may return a busy error. Disconnect drains active operations, but cancellation
does not roll back a generation already being built; normal generation and
OS-lock recovery still apply after hard termination.

Project-wide indexing remains atomic per bundle, not across bundles: a later
bundle's failure does not roll back an earlier completed index. Only MCP
adapter orchestration changes; the engine's validation report, schemas, Profile
packages, bundle content, and storage formats are unchanged.

## Options considered

- Shell-only invocation was rejected because agents need typed discovery,
  validation, and result handling.
- An HTTP server was deferred because the supported use is a local process and
  does not yet require network hosting or authentication.

## Consequences

The server reuses CLI behavior rather than defining a second validation or
retrieval contract. A shared long-lived model would need measured benefit
and explicit concurrency, cancellation, and replacement rules. Protocol
and native tests verify discovery, input validation, report parity, recovery,
stdio framing, and resource cleanup. Current tool arguments and operational
limits live in the [CLI guide](../../packages/wayfinder_cli/README.md).

## Reconsider when

Reopen the transport or lifecycle decision when a real deployment requires
remote hosting, authentication, shared warm model state, or stronger
cancellation and concurrency guarantees.
