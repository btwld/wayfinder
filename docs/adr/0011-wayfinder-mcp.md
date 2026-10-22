# ADR-0011: Serve Wayfinder tools over local MCP stdio

- Status: accepted
- Date: 2026-09-09
- Updated: 2026-10-16 (project-wide discovery across configured bundles); 2026-10-20 (retained encoder, snapshot cache, and Markdown search output); 2026-10-22 (search during an index serves the last published index; only indexes are busy)
- Scope: local MCP adapter; no Profile rule
- Builds on [ADR-0010](0010-wayfinder-cli.md)

## Context

Agents need Wayfinder validation and retrieval without parsing shell output
or maintaining another search implementation. Upstream `okf mcp` serves
format-level reads and writes; it does not replace Wayfinder's gate or
semantic search. A project can hold its own knowledge and installed reference
bundles, and an agent needs one search across them, as the CLI already
provides.

## Decision

Run `wayfinder mcp` as a local stdio server over the project's configured
bundles, using the same discovery boundary and conventional `knowledge/`
fallback as CLI project search. Discovery runs on each call and never fetches
sources. Search uses one query embedding and one global result limit and keeps
bundle-aware citations. Index explicitly refreshes every selected bundle; a
missing or stale index fails search rather than returning a subset, except
while a refresh of it runs, when search serves the last published index with
a notice ([ADR-0010](0010-wayfinder-cli.md)). Validation
and graph stay independent per bundle, returned under `bundles` with each
bundle's name and project-relative path. Validation gates and graph node
identities are never merged across bundles.

An explicit `wayfinder mcp <bundle>` binds to that canonical bundle at startup
and keeps the single-bundle result shapes. A nonblank `WAYFINDER_KNOWLEDGE_DIR`
selects that mode when no argument is given. Tool arguments cannot select an
arbitrary path or retrieval mode.

Use the MCP SDK for transport, negotiation, and framing, and Ack for argument
validation and defaults. Stdout carries JSON-RPC only; diagnostics go to
stderr. Dependency versions live in the
[package manifest](../../packages/wayfinder_cli/pubspec.yaml).

Expose the CLI's `validate`, `index`, `search`, and read-only `graph`
([ADR-0012](0012-wayfinder-graph-projection.md)) services. Return `validate`,
`index`, and `graph` results as JSON in one text content block, and `search`
results as Markdown in one text content block. A validation report with failing
findings is a completed result with an `exit_code`, not a failed tool call;
execution failures use `isError` without ending the session. Search returns
candidate passages, citations, and notices, not an answer-confidence claim.

Discovery and validation need no model. Indexing is explicit and writes only
derived app data. Tool annotations mark read-only calls and non-destructive
indexing, while the host controls approval. There is no HTTP host,
authentication, or bundle-authoring tool.

The server retains one lazily opened encoder and a bounded verified snapshot
cache across retrieval calls, evicting the encoder on failure and disposing it
on disconnect. Calls share the encoder one call into the model at a time, a
batch of passages or a query, so a search runs between an index's batches
rather than after the whole index. Searches take no lock: during an index, the
server's own or another process's, they read the last published generation.
A second index of a bundle while one runs fails as busy. Disconnect drains
active operations, but cancellation does not roll back a generation already
being built. Indexing is atomic per bundle, not across bundles: a later
bundle's failure does not roll back an earlier completed index.

## Options considered

- Shell-only invocation was rejected because agents need typed discovery,
  validation, and result handling.
- An HTTP server was deferred because the supported use is a local process.

## Consequences

The server reuses CLI behavior rather than defining a second validation or
retrieval contract; the engine's report, schemas, Profile packages, bundle
content, and storage formats are the same as on the command line. Current tool
arguments and limits live in the
[CLI guide](../../packages/wayfinder_cli/README.md).

## Reconsider when

A real deployment needs remote hosting, authentication, or stronger
cancellation and concurrency guarantees.
