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
when present. Only the bundle root `.okf.lock` protocol file is excluded by default.
`open(inventoryPolicy: KnowledgeInventoryPolicy.excludeHiddenDirectories)`
prunes dot-prefixed directories recursively while retaining hidden regular files;
this is an explicit browsing scope, not a new OKF/Profile rule. References into
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
capture/projections when its `manifestFingerprint` matches. Changed/initial
captures compare two full scans, with one retry on mutation. This catches
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
**unavailable/not assessed**. Optional
`snapshot.assessBundle(bundleId, assessor)` prepares an in-memory
`KnowledgeBundleAssessmentInput` from the same retained files. Assessment
excludes `.okf.lock` at every depth and sorts full relative paths like the OKF
loader; nested coordination files remain readable in the browsing inventory.
The host owns Profile selection using the input's captured
`wayfinder.json`/`wayfinder.lock`,
Profile fetching outside this backend, shared attempts, retries and executors.
The callback may run `input.validate(selection)` synchronously, or pass input
and selection to a top-level helper that calls
`Isolate.run(() => input.validate(selection))`. Keeping that helper outside a
closure that also captures a lease avoids sending unsendable futures to an
isolate. The result carries the snapshot's project ID and revision; discard
results for an obsolete displayed revision or changed assessment inputs.

`validate` calls `ProfileValidator.validateLoaded` with live external-path I/O
replaced. A Profile rule requiring an uncaptured path outside the bundle fails
explicitly with `KnowledgeFailureCode.unavailable`; it never guesses existence.
A hidden-directory exclusion policy makes bundle assessment `unavailable`
because OKF/Profile checks require a complete inventory. Malformed Markdown/UTF-8
refuses assessment with `invalidContent` rather than validating a partial bundle. Full malformed-file report parity and coherent
external-target observations remain deferred. The exposed `loaded` input has a
synthetic root used for diagnostics only; custom validators must also replace
external-target checks. Validation results are not cached: a later Profile cache
fill can reassess the same lease without rereading source files.

Run the workspace contributor checks and this package's `dart test` on Linux.
No model/native retrieval or other-platform verification is required or claimed.
