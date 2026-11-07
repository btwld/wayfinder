# wayfinder_reader

Pure Dart, model-free knowledge browsing contracts and a retained-byte memory
backend. No Flutter, filesystem, OKF loader, embeddings or native runtime.
This is an unpublished 0.1 API; it does not change core's prepared 0.5 contract.

`KnowledgeProject.refresh()` returns an independently releasable
`KnowledgeProjectSnapshot`. Its bundles expose concepts, a complete permitted
file inventory, a graph (or typed refusal) and explicit validation-unavailable.
`read(handle)` returns immutable verified bytes, with strict UTF-8 decoding and a
caller byte limit. Binary or malformed content is not discarded.

Identity, project-relative display paths and opaque content revisions are
separate. Handles contain project ID, optional bundle ID, snapshot revision and
safe POSIX scope-relative path. A null bundle identifies project configuration.
`CapturedKnowledgeProject` currently gives every bundle the whole-project capture
revision. This is correct but conservative: unrelated bundle/config changes can
invalidate a bundle view; these are not independent per-bundle versions.
They contain neither absolute roots nor credentials. Paths are never decoded
into permission, and handles must belong to the lease's permitted inventory.

## Backends and ownership

`MemoryKnowledgeProject(id: ..., capture: ...)` uses `KnowledgeCapture`, captured
files and semantic bundle projections. Updating `current` affects only later
refreshes. Captures defensively retain bytes and nested concept metadata. Their
SHA-256 revision covers bytes and projected content, not a load counter. Nested
YAML metadata preserves scalar mapping keys, dates and nonfinite numbers; all
returned mappings/collections are immutable rather than coerced to JSON.
`CapturedKnowledgeProject` supplies the same lifecycle to an adapter with a
private asynchronous capture callback; adapters own their acquisition bounds
and semantic correctness. It deliberately provides no filesystem abstraction.

Every successful refresh receives a distinct lease, even when capture is
coalesced. Cancelling one refresh does not cancel another. Bundle views borrow
the parent lease. Release immediately rejects access through that lease, drains
its accepted reads and drops its retained capture reference; other leases work.
Close rejects new work, invalidates all leases and drains accepted capture/reads.
Closed/revoked state takes precedence over a late capture error; while open,
original acquisition errors are preserved.
Both are idempotent, including reentrant close notifications.

`revocations` synchronously announces permanent grant loss; retained reads then
deny and consumers must clear affected views. Detached immutable values already
returned cannot be recalled. A transient refresh failure does not revoke an old
lease. Controllers borrow projects: detach UI, close controller, then close the
host-owned project. No search/status/index/model methods are mandatory or faked.
Full validation and optional search integration are deferred, not successful.

Run `dart analyze --fatal-infos` and `dart test` from the repository workspace;
see [contributor checks](../../docs/contributing.md#checks). Runtime verification
is Linux-only; portable source does not establish other platform support.
