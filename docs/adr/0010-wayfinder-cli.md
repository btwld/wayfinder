# ADR-0010: One CLI validates, indexes, and searches local knowledge

- Status: accepted; retrieval mode exposure superseded by [ADR-0017](0017-dense-only-retrieval.md)
- Date: 2026-09-09
- Updated: 2026-10-18 (dense-only retrieval in [ADR-0017](0017-dense-only-retrieval.md)); 2026-10-20 (retained MCP encoder and Markdown search output); 2026-10-22 (indexes namespaced by configuration, bundle-relative chunk IDs, the lifecycle in a library)
- Scope: application commands and the local index lifecycle; no Profile rule
- Builds on [ADR-0009](0009-local-knowledge-retrieval.md)

## Context

The validation library and the retrieval library serve different purposes.
Users and agents need one application with an explicit bundle path and an
arbitrary query, without making semantic retrieval part of Profile
conformance.

## Decision

Expose `wayfinder validate`, `wayfinder index`, and `wayfinder search`.
Validation runs the engine contract and needs no model.

The application indexes with verified local Arctic XS embeddings and searches
saved document vectors with an encoded query. Both the application and the
reusable library use dense-only retrieval ([ADR-0017](0017-dense-only-retrieval.md));
retired lexical and hybrid mode choices are rejected. Build tooling
owns model acquisition, and the native distribution includes the verified
artifact. Runtime commands never download or train a model.

Persist one derived ObjectBox index per canonical bundle path and
configuration in per-user application data, outside the repository, under
`indexes/<bundle key>/<configuration key>/`. The configuration key hashes the
chunking, snapshot and storage configuration with the encoder's identity, so
indexes built for another model, chunker or format never share a directory;
each costs one build. The bundle key is not the bare path hash 0.2 used, so
a 0.2 index is never read, changed or deleted. Chunk IDs hash each chunk's
bundle-relative identity, not the absolute root, so the same bundle in two
worktrees has the same IDs and ranks alike. Store original inputs, passages,
citations, metadata, and graph-reconstruction inputs so search reopens a
completed snapshot without re-fitting documents. An index update reuses
compatible vectors in a private generation and atomically publishes only a
completed, closed generation; the previous generation survives a failure.

Serialize operations on the same index with an OS lock
([ADR-0018](0018-embeddable-libraries.md)). Compare source hashes and the
inventory okf's loader sees, which leaves out okf's `.okf.lock`, to detect
edits; search refuses an absent, stale, or incompatible index and directs
the caller to `wayfinder index`. Search
includes every lifecycle state and bounded relationship context, following
typed `relationships` entries before untyped body links, and never derives
authority from type, verification, or similarity. MCP retains one lazily opened
encoder across serialized retrieval calls, evicting it on failure and disposing
it on disconnect, while one-shot CLI commands open and close their own encoder.

The lifecycle is a library, `wayfinder_embeddings/knowledge_store.dart`
([ADR-0018](0018-embeddable-libraries.md)); the CLI and MCP server are its
host. Its `forget` deletes a bundle's indexes, and `prune` those of bundle
roots that no longer exist and of other configurations left unused.

## Consequences

Indexes duplicate bundle text in local app data and can be removed and
rebuilt. Upgrading from 0.2 builds each bundle's index once; the 0.2 index
stays until it is deleted by hand. Staging may briefly need room for two
databases. Hash checks are not an adversarial filesystem transaction, and
atomic publication is not a power-loss guarantee.

The application has no watcher, answer generator, or automatic bundle fix
beyond `validate --fix`. Reindex after edits. Current commands and storage
details live in the [CLI guide](../../packages/wayfinder_cli/README.md).

## Reconsider when

A real consumer needs remote hosting, a different persistence guarantee, or a
retrieval mode that cannot stay an explicit, inspectable command contract.
