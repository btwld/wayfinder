# ADR-0010: One CLI validates, indexes, and searches local knowledge

- Status: accepted
- Date: 2026-09-09
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
saved document vectors with an encoded query. It has no retrieval-mode flag;
the reusable library keeps lexical and hybrid alternatives. Build tooling
owns model acquisition, and the native distribution includes the verified
artifact. Runtime commands never download or train a model.

Persist one derived ObjectBox index per canonical bundle path in per-user
application data, outside the repository. Store original inputs, passages,
citations, metadata, and graph-reconstruction inputs so search reopens a
completed snapshot without re-fitting documents. An index update reuses
compatible vectors in a private generation and atomically publishes only a
completed, closed generation; the previous generation survives a failure.

Serialize operations on the same bundle with an OS lock. Compare source hashes
and inventory to detect edits; search refuses an absent, stale, or
incompatible index and directs the caller to `wayfinder index`. Search
includes every lifecycle state and bounded relationship context, following
typed `relationships` entries before untyped body links, and never derives
authority from type, verification, or similarity.

## Consequences

Indexes duplicate bundle text in local app data and can be removed and
rebuilt. Staging may briefly need room for two databases. Hash checks are not
an adversarial filesystem transaction, and atomic publication is not a
power-loss guarantee.

The application has no watcher, answer generator, or automatic bundle fix
beyond `validate --fix`. Reindex after edits. Current commands and storage
details live in the [CLI guide](../../packages/wayfinder_cli/README.md).

## Reconsider when

A real consumer needs remote hosting, a different persistence guarantee, or a
retrieval mode that cannot stay an explicit, inspectable command contract.
