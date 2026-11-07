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
resolve selected Profiles. Supplied bundle IDs can survive relocation; fallback
IDs are explicitly location-bound. Display paths are not identities.

## Capture and access limits

Inventory includes every regular bundle file (malformed Markdown, indexes,
logs, attachments, hidden files), plus root `wayfinder.json`/`wayfinder.lock`
when present. Only the bundle root `.okf.lock` protocol file is excluded. Links
and nonregular devices are not granted inventory; linked configuration, bundle
roots or path traversal refuse. POSIX resource paths must be portable safe
relative addresses; no parent, empty or dot segments, backslashes, colons or
ASCII/C1 control characters. Unsupported filesystem addresses return a typed, file-specific
`invalidContent` refusal; they are not an added OKF conformance rule. An invalid
semantic concept ID instead retains its raw file and refuses the graph. External
Markdown references confer no file-open permission.

Each scan enforces **16 MiB per file and 64 MiB aggregate retained source bytes**
by default; hosts can lower or explicitly raise both at `open`. A bounded read
also checks size and SHA-256. Two full scans compare byte manifests and discovery,
with one retry on mutation. Up to two scan-sized raw captures coexist during
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
returning a misleading empty success. Validation is **unavailable/not assessed**:
full conformance still needs the narrow core external-target observation seam
and captured Profile selection. This package never substitutes partial OKF
checks for full `wayfinder validate`, and never reports PASS.

Run the workspace contributor checks and this package's `dart test` on Linux.
No model/native retrieval or other-platform verification is required or claimed.
