# ADR-0011: Serve Station tools over local MCP stdio

Status: Accepted

## Context

Station already owns profile validation and persistent local embedding search.
Agents need those same operations without shell parsing or separate retrieval
implementations. Upstream `okf mcp` provides format-level concept reads, graph
queries and writes; its validation checks OKF, and its concept listing is not
Station's semantic search. The two servers have different responsibilities.

## Decision

Add `station mcp <bundle>` to the existing binary, with one canonical bundle
selected at startup. Expose `validate`, `index` and `search` using the existing
Station services. MCP arguments cannot select another bundle or a retrieval mode.
This changes no OKF meaning, profile rule, or profile release.

Use `mcp_dart: ^2.4.2` directly. At the review date, 2026-09-09, this is the
latest stable SDK and is already resolved transitively through `okf 0.3.0`.
The SDK retains Dart 3.4 compatibility, so Station's Dart 3.10.7 minimum need
not change. Version 2.4.2 bounds incoming stdio frames at 10 MiB by default;
retain that limit. The SDK's default protocol profile supports current
discovery and older initialization. Test both with its client.

Use stdio for a locally launched process. Stdout carries JSON-RPC alone;
diagnostics use stderr. Delegate framing, schema validation, negotiation and
transport closure to the SDK. HTTP hosting, authentication, Tasks and bundle
authoring are outside this change.

Results carry the CLI's JSON once in a text content block, following upstream
OKF's MCP convention. This avoids sending two copies of every passage to clients
that consume both text and structured content. Search includes original path and
line citations, metadata, scores, context reasons and notices. It makes no answer
confidence claim. Validation retains its report and `exit_code`; findings are a
completed report, not a failed tool invocation. Index/search failures return
`isError` and leave the session usable.

Discovery and validation require no model. Indexing is explicit, writes only
derived local app data and reuses compatible vectors. Search encodes only its
query and refuses stale indexes. Tool annotations describe validation/search as
read-only and index as a non-destructive, idempotent local write. The host owns
the invocation approval policy.

## ACK adapter trial

Station now registers tool arguments through `ack_mcp_dart` from
[ACK PR #140](https://github.com/conceptadev/ack/pull/140), pinned to
`1b54b08e522c9dee51cfa55ac69f8448bd2a3b72`. It depends on the published
`ack ^1.2.0` core; no workspace dependency override is needed.

ACK owns schema export and runtime defaults/normalization. The search callback
receives an integer limit, including when the client sends `2.0`, and no longer
performs its own numeric conversion or defaulting. Closed objects, nonblank
queries and the 1–100 bounds remain the same. The adapter provides reusable
validation behavior; this small integration still uses validated map arguments
and does not justify adding generated models solely for two fields.

This is a modest maintainability improvement, not a model-performance change.
The temporary Git pin makes the trial reproducible; switch to a released adapter
after verifying that release. Transport, lifecycle, output reports and native
startup behavior remain owned by their existing components.

## Lifecycle and limits

Each index/search call opens and disposes its own model and store, preserving
the CLI's freshness and lock behavior. Overlapping retrieval calls can return a
busy error; they are not silently queued or replayed. Disconnect drains active
operations so their cleanup runs. Cancellation does not undo an index generation
that is already being built; an operation can finish publishing after its client
disconnects. Hard process termination still relies on the existing generation
and OS-lock recovery behavior.

This first adapter does not amortize model initialization across requests.
A retained engine needs explicit concurrency, cancellation and model-replacement
rules and a measured latency benefit before adding shared lifetime management.
Clients should allow sufficient time for initial native startup and corpus-sized
indexing. Native initialization remains variable and can hit llamadart's
30-second worker timeout; a macOS CI retry passed the same startup test without
changing code. That does not establish a permanent fix for the upstream delay.

## Validation

Protocol tests cover both supported negotiation paths, tool discovery, argument
rejection, validation parity, bound-root delegation, recovery after a tool error
and cleanup after disconnect. The relocated native check uses generic fixtures,
real embeddings and ObjectBox to exercise missing assets, vector reuse, source
edits, metadata refresh and persistence across server restarts. It also checks
that every stdout line is JSON-RPC. CI runs this check on Linux and macOS.

## References

- [mcp_dart 2.4.2 release notes](https://pub.dev/packages/mcp_dart/changelog)
- [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP tools and result conventions](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [Upstream OKF MCP](https://github.com/conceptadev/okf#model-context-protocol)
- [Station CLI decision](0010-station-cli.md)
