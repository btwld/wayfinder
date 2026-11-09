# wayfinder_reader_local

Read-only local files behind the [portable reader](../wayfinder_reader/README.md),
using core configuration parsing and OKF's in-memory document/graph APIs. No
embeddings dependency, model provisioning, index, Profile fetching or cache
restoration. This unpublished backend changes no OKF/Profile/validator semantics.

```dart
final project = await LocalKnowledgeProject.open(
  root: Directory('/granted/project'), id: 'host:project',
  bundleIds: {'knowledge': 'host:stable-docs'},
);
final snapshot = await project.refresh();
final bytes = await snapshot.read(snapshot.files.first.handle);
await snapshot.release();
await project.close();
```

Discovery uses only the granted root's `wayfinder.json` (`applies_to` through the
core parser), or conventional `knowledge/`. It does not search ancestors or
resolve selected Profiles. An existing project with neither configuration nor
`knowledge/` returns a successful snapshot with no bundles; a missing project or
a missing configured bundle returns `notFound`. Supplied bundle IDs can survive
relocation; fallback IDs are explicitly location-bound. Display paths are not identities.

## Capture and access limits

Inventory includes every regular bundle file (malformed Markdown, indexes,
logs, attachments, hidden files), plus root `wayfinder.json`/`wayfinder.lock`
when present. The bundle root `.okf.lock` protocol file is excluded. Dot-prefixed directories
(including `.git` and `.okf` caches) are pruned recursively by default, while
hidden regular files remain included. `open(includeHiddenDirectories: true)`
opts into hidden directories. This controls captured scope; `loadBundle` works
with either setting and does not gate validation based on the flag. References into
excluded inventory gain no read permission. Links
and nonregular devices are not granted inventory; linked configuration, bundle
roots or path traversal refuse. POSIX resource paths must be portable safe
relative addresses; no parent, empty or dot segments, backslashes, colons or
ASCII/C1 control characters. Unsupported filesystem addresses return a typed, file-specific
`invalidContent` refusal; they are not an added OKF conformance rule. An invalid
semantic concept ID instead retains its raw file and refuses the graph. External
Markdown references confer no file-open permission.

Each scan enforces **16 MiB per file and 64 MiB aggregate retained source bytes**
by default; hosts can lower or explicitly raise both at `open`. A bounded read
also checks size and SHA-256. An unchanged refresh performs one full byte scan and reuses the previous
capture/projections when the capture's `manifestFingerprint` and external
existence observations match. Changed/initial
captures compare two full scans and their external observations, with one retry
on mutation. This catches
same-size edits even with restored mtimes; it is not a stat-only cache.
Concurrent refreshes coalesce capture but return independent leases. The latest
capture stays cached until replaced or project close; old leases retain their
own captures. Sequential idle refreshes still scan once each; hosts should
coalesce/debounce focus and watcher notifications if that cost matters. Up to two scan-sized raw captures coexist during
comparison (plus bounded temporary reads, semantic models and consumer copies).
This is not a project transaction, lock/snapshot filesystem, or protection
against adversarial replacement/ABA races. No source files or lock files are
written. Source operations stay on one isolate.

All captured bytes are retained, including attachments, so an old revision never
substitutes fresh filesystem bytes. Reads recheck project/lease/grant state and
handle membership, not live file freshness. Changed sources appear only after
explicit successful refresh; transient refresh failure leaves the old authorized
lease readable. Host-observed grant loss calls `revoke()` immediately, clearing
attached controllers and denying even retained reads. New permission requires a
new project. OS failures alone are not treated as grant revocation.

Concepts/graph derive only from captured Markdown via OKF. Both ordinary edges
and Wayfinder relationship field edges retain origins, resolutions and names.
Malformed Markdown remains raw-readable and refuses the graph rather than
returning a misleading empty success. Bundle browsing views keep validation
**unavailable/not validated**. `snapshot.loadBundle(bundleId)` returns the
reader's plain `KnowledgeRetainedBundle` value. The single native conversion is:

```dart
final loaded = buildOkfBundle(snapshot.loadBundle(bundleId));
```

`buildOkfBundle` is a top-level function, with no callback/class/interface. It
uses core's `classifyBundleFile` for indexes, logs, concepts and assets, and
excludes `.okf.lock` at every depth. The reader value still retains nested
coordination files. The shared classifier is also used by browsing projections,
external-target capture, core adoption and query fingerprinting, so their file
roles agree. Malformed Markdown/UTF-8 throws `invalidContent` from the builder;
the reader never parses it. Full malformed-file report parity remains deferred.

The resulting `rootPath` is core's `retainedBundleRoot`, a non-filesystem sentinel.
`ProfileValidator.validateLoaded` throws a `StateError` naming the missing
`outsideBundleExists` callback when it receives this root without observations,
before validation can read disk. The resolver also refuses a direct outside-path
query using the sentinel without a callback. Ordinary on-disk roots keep their
existing behavior.

At capture time, `externalPathTargets` in core enumerates a superset of all
outside paths the `path-targets-exist` builtin could ask about, across every
supported field, without requiring Profile configuration or fetching. This
backend observes existence only within the granted root, without traversing
symlinks or reading target content. Unreadable, symlinked or out-of-grant targets
remain unknown. `snapshot.externalPathObservations[bundleId]` holds immutable
booleans keyed by decoded, normalized bundle-relative outside paths. Observed
absence is `false`; missing keys are unknown and must throw `unavailable` when
queried. Existence is compared alongside both capture manifests; refresh also
rechecks it before reusing the previous capture. Changes affect the snapshot
revision even when every retained file byte stays the same. This remains a
best-effort capture, without a filesystem transaction or adversarial-race promise.

The host can validate the returned load on its own isolate using only captured
observations, never live external disk lookup:

```dart
final observations = snapshot.externalPathObservations[bundleId] ?? const <String, bool>{};
final validator = ProfileValidator(outsideBundleExists: (path) =>
  observations[path] ?? (throw KnowledgeFailure(
    KnowledgeFailureCode.unavailable, 'validate', 'No captured observation.', path: path)));
final loaded = buildOkfBundle(snapshot.loadBundle(bundleId));
// Pass loaded, selection and observations to a top-level Isolate.run helper.
```

Profile selection must use the displayed `wayfinder.json`/`wayfinder.lock`
bytes. Fetching, shared attempts, retries, execution bounds, cancellation and
revision/context checks belong to the host. A later Profile cache fill can
validate the same load again without rereading source files. The inventory flag
never gates validation; conformance applies to the captured inventory, which
can intentionally differ from an unfiltered on-disk load under hidden directories.

Run the workspace contributor checks and this package's `dart test` on Linux.
No model/native retrieval or other-platform verification is required or claimed.
