# wayfinder_reader

Pure Dart, model-free knowledge browsing contracts and a retained-byte memory
backend. No Flutter, filesystem operations, embeddings or native runtime.
The runtime import closure is browser-compatible and excludes OKF and core
Wayfinder. Native OKF conversion lives in the existing reader_local package.
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
Close rejects new work, invalidates all leases and drains accepted captures
and reads.
Closed/revoked state takes precedence over a late capture error; while open,
original acquisition errors are preserved.
Both are idempotent, including reentrant close notifications.

`revocations` synchronously announces permanent grant loss; retained reads then
deny and consumers must clear affected views. Detached immutable values already
returned cannot be recalled. A transient refresh failure does not revoke an old
lease. Controllers borrow projects: detach UI, close controller, then close the
host-owned project. No search/status/index/model methods are mandatory or faked.
Validation stays unavailable on browsing views. `snapshot.loadBundle(bundleId)`
returns a `KnowledgeRetainedBundle`: its `id`, captured `summary`, and immutable
`files` (`KnowledgeCapturedFile` path/bytes values), sorted by full relative path.
Only the bundle root `.okf.lock` is excluded. It performs no Markdown parsing,
classification or I/O; malformed/binary bytes remain bytes. Unknown bundle IDs
throw `notFound`. A detached value survives lease release/revocation.

Native hosts convert the value with
`buildOkfBundle(snapshot.loadBundle(bundleId))` from
[reader_local](../wayfinder_reader_local/README.md), where OKF parsing belongs.
Hosts own Profile selection from captured configuration/lock bytes, isolate
execution, cancellation and result publication. In this six-line example,
`validateApart` is the host's native helper that builds the OKF load and validates
it in an isolate using only the supplied observations. Its context token must
change on release, revocation, project switch or a new Profile attempt:

```dart
final context = currentContext;
final revision = snapshot.revision;
final retained = snapshot.loadBundle(bundleId);
final observations = snapshot.externalPathObservations[bundleId] ?? const <String, bool>{};
final result = await validateApart(retained, selection, observations);
if (currentContext == context && displayedRevision == revision) publish(result);
```

`externalPathObservations` is an immutable map by bundle ID, then decoded
bundle-relative outside path, then existence. Missing entries are unknown, never
false or permission to consult live disk. Memory captures default to no
observations; adapters may provide them explicitly. Observations are part of the
full revision; they do not change the byte-manifest fingerprint.

`KnowledgeCapture.manifestFingerprint` is a SHA-256 of sorted file
addresses/digests and bundle identities/paths, independent
of semantic projections and enumeration order. The pure
`knowledgeManifestFingerprint` function computes the same identity from file
addresses/digests and bundle identities/paths. It covers configuration/lock
bytes when captured. Use revision plus Profile/validator inputs for validation
caching; the manifest alone cannot identify a changed Profile selection.
Optional search integration remains deferred.

Run `dart analyze --fatal-infos` and `dart test` from the repository workspace;
see [contributor checks](../../docs/contributing.md#checks). CI runtime verification
is Linux-only; these checks do not establish other platform support.
