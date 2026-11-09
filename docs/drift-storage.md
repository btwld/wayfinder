# Drift index storage

Wayfinder persists new indexes in an immutable SQLite database per generation,
using typed Drift tables and sqlite3. The production `KnowledgeIndex` still
scores every eligible vector in Dart, with its existing filters, tie ordering,
context selection and citations. No SQLite vector extension or approximate
candidate selection is involved. This replaces persistence, not retrieval.

## Schema and ownership

Schema version 1 contains `stored_chunks` (stable text primary key, explicit
ordinal, path, line range, content, type and JSON metadata), `stored_embeddings`
(composite chunk/source/model primary key, chunk foreign key with cascading
delete, dimension and little-endian float32 BLOB), and `generation_records`
(singleton canonical record JSON and SHA-256). Chunk ordinals preserve source
snapshot order independently of SQLite row order.
An ordinal index supports ordered reads and the mutable store's next-ordinal
lookup; incoming batches query only their IDs and ordinals, and embedding-only
writes do not read chunks. CHECK constraints enforce
positive dimensions, vector byte lengths and valid line ranges; the Dart codec
also rejects nonfinite and all-zero float32 vectors before writes and after
reads. Generation loading checks SQLite integrity/foreign keys, the record
hash, snapshot/count/input identity, exact chunk projections and the vector
checksum before exposing a snapshot. Valid SQLite alone is insufficient.

The database backend owns opening, typed queries, transactions and awaited
closure. Native database work runs in a Drift background isolate. A write
transaction contains only prepared rows; source parsing, token counts, model
inference and filesystem inventory checks happen before it. `DriftStore`
implements the generic `BaseStore` API for library consumers with the same
exhaustive Dart cosine ordering and transactional replacement, and supports
multiple model identities and dimensions. Its database is mutable; published
knowledge generations are immutable.

Drift's `user_version` is the schema version; SQLite's `application_id` is
`0x57465354` (ASCII `WFST`) and identifies Wayfinder's storage format. Existing
files must carry both supported markers before writer initialization can change
journal settings. Typed projections also reject damaged table layouts on open.
Creation is explicit, opening a missing generation never creates one, and
unknown/newer versions fail closed.
Future versions require an explicit migration path and fixtures; absent such a
path they are refused, never opened as an empty database. Published generations
are read without migration; a future migration writes a replacement generation.
The canonical snapshot's existing version is independent of the database version.

## Publication and coherent reads

The namespace, configuration/model identity, writer lock, generation names,
`current` pointer, grace period, retry policy, pruning and forget operations
remain the existing protocol. A writer prepares `generation-<id>/index.sqlite`,
commits, verifies and closes the database, flushes the completed file, then
atomically replaces `current`. SQLite uses rollback journaling for these files;
publication never relies on a WAL or shared-memory sidecar. Failure or
cancellation before publication removes staging and preserves the old pointer.
No network or embedding work occurs in a transaction. A crash can leave an
unpublished generation, which existing garbage collection can reclaim.

A reader pins one pointer value and loads the complete verified generation
before scoring. Connections are closed before the operation uses its in-memory
snapshot, so refresh, prune and disposal cannot switch half a query to another
version. If a pinned generation disappears, existing pointer retries apply.
Refresh continues serving the previous snapshot under the existing stale-index
policy and notices. Source freshness and model identity checks remain unchanged.
The configuration key retains its historical `f32-v1` identity because chunking,
model and float32 meaning did not change; `index.sqlite` and its schema version
discriminate persistence. The canonical record retains its `vectors.file` /
`format` descriptor for the f32-v1 checksum envelope, including its dimension
and count header; SQLite stores only the individual row BLOBs, and writes no
legacy vector file. This keeps the checksum and strict legacy decoder common
without introducing a second writer. Changing the configuration hash merely
for storage would strand otherwise reusable vectors.

## Compatibility and migration

| Input | Search/status | Explicit `index` | Older binaries |
| --- | --- | --- | --- |
| Current verified `snapshot.json` + `vectors.f32` generation | Read without mutation | Publish SQLite, reuse unchanged valid vectors | Can still read that old generation |
| SQLite schema 1 | Read and validate | No-op if current; otherwise incremental replacement | Cannot read the new generation |
| Missing or corrupt current generation | Existing missing/incompatible refusal | Rebuild from sources | No compatibility promise |
| Unknown/newer SQLite schema | Incompatible refusal | Explicit rebuild may replace it; no in-place downgrade | Refuse/unsupported |
| Older ObjectBox/0.2 namespaces | Never open, modify or delete | Build current namespace as before | Existing older release behavior |

The only legacy implementation retained is a strict read-only decoder for
current plain-file generations. It verifies header, dimensions, row count,
SHA-256, finite/nonzero vector data, snapshot and input counts before reuse.
Migration occurs only through explicit indexing and never re-embeds unchanged
valid data merely to change storage. There is one writer: SQLite. Old immutable
generations remain subject to the documented grace/garbage-collection policy;
source files and unrelated old namespaces are untouched. A migration is a new
publication, not an in-place rewrite. Retire the reader only in an explicitly
announced compatibility-breaking release after a migration window.

Rollback requires retaining/restoring the old `current` pointer and its complete
old generation before garbage collection, or reindexing with the old binary in
a separate data directory. Downgrades cannot read SQLite generations; no automatic
reverse writer or downgrade migration is provided.

## Optional library API break and cleanup

`ObjectBoxStore`, its schema/entity helpers, ANN knobs, native installer/assets,
generator, generated model and dependencies are removed. Use asynchronous
`DriftStore.open` and await `close`; ObjectBox databases are not imported by the
generic library store. This is a breaking optional Dart API change and is
released as `wayfinder_embeddings` 0.6.0-beta.1, with dependent constraints
updated. Wayfinder CLI/MCP and `WayfinderKnowledgeStore` APIs remain stable.
Native CLI bundles use sqlite3's native-asset build output and licenses instead
of a separately downloaded ObjectBox runtime. Historical decision/release notes
and fixtures proving ignored older namespaces may still mention ObjectBox.

## Verification gates

Existing public output goldens and exact score/citation expectations stay intact.
Production store tests cover initial/no-op/edit/delete indexing, current legacy
migration without inference, corrupt legacy refusal/rebuild, missing/newer schema,
float32/JSON/order round trips, transactional rollback, failed/cancelled staging,
refresh/concurrent readers, pointer pin/GC races, prune/forget and disposal.
Generic store contracts run against Drift as well as memory. Schema/native tests
cover reopen, keys/FKs and closed connections; packaged native CLI smoke checks
relocation and actual model search when the local model is available. Package
test runs are serialized as required by the contributor guide. Cross-platform
native artifacts remain subject to their existing release verification policy.

Authoritative implementation references: [Drift native platforms](https://drift.simonbinder.eu/platforms/vm/),
[migrations](https://drift.simonbinder.eu/migrations/),
[transactions](https://drift.simonbinder.eu/dart_api/transactions/) and
[tables](https://drift.simonbinder.eu/dart_api/tables/).
