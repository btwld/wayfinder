# ADR-0010: Wayfinder validates, indexes, and searches local knowledge

- Status: accepted
- Date: 2026-09-09
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0010-station-cli.md))
- Scope: application commands and local index lifecycle; no Profile rule changes
- Builds on [ADR-0009](0009-local-knowledge-retrieval.md)
- Amended 2026-10-01 for Profile 2026.3: declared-relationship context also
  follows the `relationships` frontmatter key (Bitwild rule [`relationship-shape`](../../profiles/bitwild/README.md#relationship-shape)),
  read from the saved sources when an index reopens, so the saved index format
  is unchanged. Typed relationships are followed before untyped body links,
  and a hit reached through one names its relationship.

## Context

The validation library and retrieval library served different purposes.
Users and agents needed one application with an explicit bundle path and an
arbitrary search query, without making semantic retrieval part of Profile
conformance.

## Decision

Expose `wayfinder validate`, `wayfinder index`, and `wayfinder search`.
Validation delegates to the selected Profile validator and preserves its
independent OKF result, findings, exit codes, and unassessed judgment state.
It does not require a model.

The application indexes with verified local Arctic XS embeddings and searches
saved document vectors with an encoded query. It has no retrieval-mode flag;
the reusable library retains lexical and hybrid alternatives. Build tooling
owns model acquisition, and the complete native distribution includes the
verified artifact. Runtime commands do not download or train a model.

Persist one derived ObjectBox index per canonical bundle path in per-user
application data, outside the source repository. Store original inputs,
passages, citations, metadata, and graph-reconstruction inputs so search
reopens a completed snapshot without re-fitting documents. Index updates
reuse compatible vectors in a private generation and atomically publish only
a completed, closed generation. The previous generation survives failure.

Serialize operations on the same bundle with an OS lock. Compare source
hashes and inventory to detect observed edits; search refuses absent, stale,
or incompatible indexes and directs the caller to `wayfinder index`.
Include all lifecycle states and bounded declared-relationship context
without deriving authority from type, verification, or similarity.

## Consequences

Indexes duplicate bundle text in local app data and can be removed and
rebuilt. Staging may temporarily require room for two databases. Hash checks
are not an adversarial filesystem transaction, and atomic generation
publication is not a universal power-loss guarantee.

The application has no watcher, LLM answer generator, automatic bundle fix,
or Profile index generator. Reindex after edits. This decision changes no
bundle rules and requires no Profile migration. Current command and storage
details live in the [CLI guide](../../packages/wayfinder_cli/README.md).

## Reconsider when

Reopen the application boundary if a real consumer needs remote service
hosting, a different persistence guarantee, or a retrieval mode that cannot
remain an explicit and inspectable command contract.
