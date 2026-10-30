# ADR-0010: One CLI validates, indexes, and searches local knowledge

- Status: accepted; retrieval modes superseded by [ADR-0017](0017-dense-only-retrieval.md)
- Date: 2026-09-09
- Updated: 2026-10-18 (dense-only); 2026-10-20 (retained MCP encoder and Markdown output)
- Scope: commands and local index lifecycle; no Profile rule
- Amendments: [0018](0018-embeddable-libraries.md) (public libraries), [0022](0022-plain-file-index-generations.md) (storage and refresh reads), [0026](0026-model-cache-and-source-paths.md) (model lookup and source paths)

## Context and decision

Provide one application for `validate`, `index`, and `search`, while keeping
semantic retrieval separate from Profile conformance. Validation needs no model.
Indexing explicitly saves verified local document embeddings; search encodes the
query against that saved index and never implicitly rebuilds it. Runtime commands
never download or train models. Native distributions include the verified model.

The original ObjectBox storage and refusal of every stale index were replaced
by ADR-0022's immutable plain-file generations: search may read the previous
snapshot during a refresh, with notices. Without a refresh, stale indexes are
refused. Derived indexes live outside the repository, keyed by canonical bundle
path and configuration.

Search includes every lifecycle state and bounded relationship context, following
typed `relationships` before untyped body links. Type, verification and similarity
do not imply authority. MCP retains a lazy encoder across calls; one-shot CLI
commands own and close theirs. The [CLI guide](../../packages/wayfinder_cli/README.md)
owns current commands, runtime model lookup and source-path behavior.

## Consequences

Explicit indexing makes cost and freshness visible but requires reindexing after
edits. Local indexes duplicate bundle text and may be deleted and rebuilt;
staging needs space for old and new generations. Hash checks are not adversarial
filesystem transactions, and atomic publication is not a power-loss guarantee.
There is no watcher or answer generator. Reconsider for a concrete remote-hosting,
persistence or retrieval need that cannot fit this inspectable command contract.
