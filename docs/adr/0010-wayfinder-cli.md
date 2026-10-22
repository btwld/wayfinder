# ADR-0010: One CLI validates, indexes, and searches local knowledge

- Status: accepted; retrieval mode exposure superseded by [ADR-0017](0017-dense-only-retrieval.md)
- Date: 2026-09-09
- Updated: 2026-10-18 (dense-only retrieval in [ADR-0017](0017-dense-only-retrieval.md)); 2026-10-20 (retained MCP encoder and Markdown search output); 2026-10-22 (indexes namespaced by configuration, bundle-relative chunk IDs, the lifecycle in a library; a host may provision the model; the configuration names the reviewed llama.cpp release); 2026-10-22 (read while indexing, #110: plain-file generations instead of ObjectBox, a lock only writers take and readers only probe, serving the last generation during a refresh); 2026-10-22 (what a host found: typed search notices, cancelling a search, releasing an idle retained encoder, removing the model, and forgetting a project root's indexes with their lock files)
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
retired lexical and hybrid mode choices are rejected. Runtime commands
never download or train a model. Build tooling acquires it, and the native
distribution includes the verified artifact. A host that embeds the retrieval
library acquires it only by calling `EmbeddingModelCache.provision`, after its
user agrees. Both download the pinned artifact into a model cache, by default
in per-user application data, and verify its size and SHA-256 before an
atomic rename, so a failed download never replaces a model. Locating the model
reads files only, and so does `EmbeddingModelCache.remove`, which deletes the
model and its downloads' temporary files when the host's user no longer wants
it.

Persist one derived index per canonical bundle path and configuration in
per-user application data, outside the repository, under
`indexes/bundles/<bundle key>/<configuration key>/`. The configuration key
hashes the chunking, snapshot and storage configuration with the encoder's
identity, so indexes built for another model, chunker or format never share
a directory; each costs one build. Another llama.cpp build can change the
vectors of the same model, so the configuration also names the
`llamadart-native` release Wayfinder reviewed (`wayfinderLlamaCppRuntime`),
and moving it builds every index anew. The key cannot see which release a
build bundles, since llamadart's hook downloads the one its version pins:
Wayfinder's own builds fail when the resolved llamadart pins another release
or the workspace overrides it, and a host that shares indexes must resolve
the same release. The bundle key is not the bare path hash 0.2 used, and the
`bundles/` tree is not where earlier 0.3 builds kept ObjectBox databases, so
neither kind of earlier index is read, changed or deleted. Chunk IDs hash
each chunk's bundle-relative identity, not the absolute root, so the same
bundle in two worktrees has the same IDs and ranks alike.

An index is a sequence of immutable generations. Each holds a
`snapshot.json` record of the original inputs, passages, citations,
metadata and graph-reconstruction inputs, so search reopens a completed
snapshot without re-fitting documents, and a `vectors.f32` file: a header,
then one little-endian float32 row per passage in snapshot order, whose
dimension, row count and SHA-256 the record names. An index update reuses
compatible vectors, writes a complete new generation, and publishes it by
atomically replacing a `current` pointer; the previous generation survives a
failure. Search loads the published generation into an in-memory store and
scores every eligible vector exactly, as it did over ObjectBox, whose HNSW
index it never used: the stored vectors are the same float32 values, so
rankings do not change, and no native database library is needed.

Only writers lock ([ADR-0018](0018-embeddable-libraries.md)). An index, or
`forget`, holds the bundle's `writer.lock` for its whole run; a second
writer fails as busy instead of waiting. `status` and search hold no lock:
they read the pointer and the generation it names, which nothing changes, so
a search keeps working while an index runs (#110). They tell whether a writer
runs by probing its lock with a shared lock for an instant, which a starting
writer waits out rather than report as busy; on Windows, where a file another
handle has open cannot be replaced, a publication waits up to two seconds for
readers to close the pointer, then fails as busy. A superseded generation
is deleted only by a later publication, and only ten minutes after it was
superseded, so a reader that read the pointer just before still finds it;
a reader that loses that race anyway reads the pointer again rather than
fail. Compare source hashes and the inventory okf's loader sees, which
leaves out okf's `.okf.lock`, to detect edits; search refuses an absent,
stale, or incompatible index and directs the caller to `wayfinder index`.
While another operation holds the writer lock, the application's search
instead serves the last published generation: it adds a
`refresh-in-progress` notice, and when files changed since that generation
was built, a `source-changed` notice and a `sourceChanged` mark on their
citations. Each notice carries a stable code, its sentence and the
bundle-relative paths it concerns, so a host tells notices apart without
reading their text; the command prints the same lines. With no refresh
running, a stale index is refused as before, and the library refuses by
default. Search
includes every lifecycle state and bounded relationship context, following
typed `relationships` entries before untyped body links, and never derives
authority from type, verification, or similarity. MCP retains one lazily opened
encoder that its calls share, one call into the model at a time, so a search
can run between an index's batches. It evicts the encoder when the encoder
fails, but not on an expected refusal such as a stale or busy index, and
disposes it on disconnect, while one-shot CLI commands open and close their
own encoder. A host that retains an encoder for longer may release it at
once or once it has gone unused for a period it chooses, keeping the parsed
snapshots, and the next index run or search opens it again. A host can
cancel a search as it cancels an index: between bundles, before the query is
encoded and before passages are scored.

The lifecycle is a library, `wayfinder_embeddings/knowledge_store.dart`
([ADR-0018](0018-embeddable-libraries.md)); the CLI and MCP server are its
host. Its `forget` deletes a bundle's indexes with their lock files and the
directories they leave empty, and `forgetProjectRoot` those of every bundle
at or inside a project root, which it finds by the bundle root each index's
lock records, so a removed worktree needs no bundle list. `prune` deletes
those of bundle roots that no longer exist and of other configurations left
unused, with the `get` locks of removed projects and abandoned model
downloads.

## Consequences

Indexes duplicate bundle text in local app data and can be removed and
rebuilt; so can the model cache, at the cost of one download. Upgrading from
0.2, or from an ObjectBox-backed 0.3 build, builds each bundle's index once;
the earlier index stays until it is deleted by hand. Staging and the grace
period may briefly keep several generations. A search during a refresh can
return the previous generation's passages for edited files; its notices and
marks say so, and the cited text must be checked against the file. Hash checks
are not an adversarial filesystem transaction, and atomic publication is not
a power-loss guarantee.

The application has no watcher, answer generator, or automatic bundle fix
beyond `validate --fix`. Reindex after edits. Current commands and storage
details live in the [CLI guide](../../packages/wayfinder_cli/README.md).

## Reconsider when

A real consumer needs remote hosting, a different persistence guarantee, or a
retrieval mode that cannot stay an explicit, inspectable command contract.
