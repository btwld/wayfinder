# Integrating the model-free Flutter reader

The shared `KnowledgeReaderController` and `KnowledgeReader` consume portable
`KnowledgeProject` leases. The same widgets run against
[`MemoryKnowledgeProject`](../../wayfinder_reader/README.md) and
[`LocalKnowledgeProject`](../../wayfinder_reader_local/README.md). Hosts retain
sign-in, project selection, source grants, app chrome and lifecycle ownership.
No embedding model, search index or retrieval package is needed.

The controller has a separate per-file read/copy budget, `maxReadBytes` (16 MiB
by default). If a host raises local capture limits and wants larger files to
open in the UI, explicitly raise this controller budget too. Direct snapshot
callers retain their own `read(maxBytes: ...)` limit; inventory size never
silently increases the UI's memory budget. File labels distinguish project
configuration from bundle-relative content even when filenames match.

```dart
final controller = KnowledgeReaderController(project: project);
await controller.refresh();
final page = KnowledgeReader(controller: controller); // under MaterialApp
// After detaching the page:
await controller.close();
controller.dispose();
await project.close(); // host owns it, not the controller
```

Use [the native example](../example/README.md) for local or memory composition.
It is intentionally a minimal browsing surface: bundle/file selection, concept
body, exact raw source or bounded binary hex preview, graph, and honest
validation-unavailable. It renders no invented attachment or Markdown content,
loads no network images and follows no external URL implicitly. Existing file
tree projections, link helpers and graph widgets remain available for custom UI.

## Identity, revision and controller state

Project/bundle IDs are opaque source-scoped identities, never paths. Bundle
summaries carry project-relative display paths; concept IDs remain OKF
bundle-relative IDs. Resource handles carry a revision and safe path relative to
their bundle, or explicit project scope for config/lock. Do not construct native
paths from display labels or synthetic graph IDs. Full lease revisions identify
content; the summary integer is only a compact display/cache fingerprint.
The retained-capture backends currently use the project-wide revision for each
bundle. Changes to another bundle or project config/lock may invalidate it too;
this conservative revision is not independent per-bundle versioning.

Every refresh caller owns a distinct lease. Releasing one controller cannot
invalidate another controller sharing the project. Bundle views borrow their
parent lease. Refresh publishes only after acquisition succeeds, then releases
the old lease. Transient refresh errors retain authorized old content; grant
revocation instead clears content/results immediately. Generation checks prevent
late refresh/read/layout completions from replacing newer selection or
repopulating revoked/closed views. Controller close drains its accepted work and
releases leases; it never closes the borrowed project. Every cleanup is attempted
and accepted work drains even when an adapter's cancellation/release fails.
Background retirement failures are observed immediately and carried to awaited
`close()`, which rethrows the first cleanup error with its original stack after
all cleanup drains. Dispose-initiated failure is reported through Flutter.

Local capture retains all bounded raw bytes and compares two manifests. See its
README for limits and nontransactional filesystem guarantees. A remote backend
must supply the same revision-conditioned/retained-byte semantics; no remote
transport/provider is supplied here.

## Graph fidelity and presentation

The local backend builds `OkfGraph.fromBundle` and
`okfFieldEdges(bundle, [relationshipsLinkField])` from captured documents, not
independent reload calls. It preserves ordinary and field edges, origins,
resolutions and relationship labels. Concept targets use their canonical IDs;
nonconcept targets retain their written value. Node/edge display paths prefix
the project-relative bundle path exactly once. Malformed Markdown refuses the
graph while leaving the raw inventory readable.

`layOutKnowledgeGraph`, `knowledgeGraphScene`, canvas, painter, palette, theme,
labels and helpers keep their canonical paths/behavior. Layout owns focus,
depth, scope and layers, not source I/O. Local scope defaults to depth 1 and
clamps to 1–3; Whole bundle is opt-in. Attachment/external/unresolved layers stay
hidden unless requested. Synthetic scene IDs are opaque `/<kind>:...` values;
resolve them through scene nodes, never as concept IDs. The bundled reader opens
the whole graph only when Graph is selected. Existing custom hosts can keep
cached scenes and their own toolbar/query controls. Graph keyboard navigation
and richer Markdown rendering remain follow-up; ordinary controls are native
Flutter Material navigation.

## Explicitly unavailable, not successful

Browsing views return `KnowledgeValidationUnavailable`; the UI says **not
validated**, never PASS. Hosts validate retained bundle bytes separately using
the displayed configuration and captured outside-path observations. Core reports
and OKF → engine → Profile authority are unchanged.

Search is absent: no mandatory search/index/status/model stubs or synthetic
readiness states. Optional semantic search belongs at a future controller
injection seam after pinned-query provenance and the prepared index changes are
integrated. That future work must preserve context, statuses, notices and source
provenance, not reuse the removed lossy provisional DTOs. Remote providers,
alternate vector persistence, sync and authoring are deferred.

## Migration from unpublished 0.1

0.2 replaces provisional `KnowledgeProject.root`, `snapshot`, project-level
`concept`/`graph`/`validation`, mandatory search/index/status and
`KnowledgeSearchModel` APIs. Use `project.refresh()`, select a bundle on the
returned lease, then read concepts/graph or revision-bound raw handles. Close
borrowed ownership explicitly. `KnowledgeException` becomes typed `KnowledgeFailure` with stable failure codes.
Provisional index/search/model DTOs were removed;
there is no compatibility shim or second backend contract.

Portable concept/graph/finding values now live in `wayfinder_reader` and are
re-exported from `wayfinder_flutter` and the existing model import paths. Existing
graph/helper consumers do not need import-path changes. Existing presentation
file-entry/tree models remain projections, not an alternative source backend.
The package remains unpublished; this is an intentional breaking minor, not a
change to the stable core/CLI/retrieval contract. Sibling packages are unpublished,
so local composition needs matching overrides as demonstrated by the example.
