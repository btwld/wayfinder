# Integrating the Flutter reader

This early SDK supplies portable models, graph rendering and reader helpers.
It does not yet supply an application backend or a complete reader.
Use the existing core and embeddings libraries to build the host adapter.
This guide describes integration work; it changes no OKF, engine or Profile contract.

## Available pieces and follow-up owners

| Area | Available | Missing / follow-up owner |
| --- | --- | --- |
| Bundles and concepts | Core discovery, OKF loading and Profile validation; Flutter reader DTOs | Host adapter: concrete `KnowledgeProject`, cached snapshots, concept/backlink/stamp/validation mapping |
| Graph | Core projection; Flutter selection/layout, canvas, palette, theme and labels | Host controller: bundle/focus/scope/depth/layers, layout lifecycle, attention and navigation |
| Files | File-entry models and tree projection | Host adapter: complete inventory and raw-file reading; product: tree/attachment/reader UI |
| Search and indexing | Embeddings store, status, progress, cancellation and cited results | Host adapter/controller and product search/index UI; preserve full backend state |
| Model acquisition | Verified cache lookup and provisioning | Host: concrete `KnowledgeSearchModel`, consent mapping, native runtime and packaging |
| Reader application | Graph callbacks and semantics | Product: remaining reader widgets, runnable example and graph keyboard navigation |

The interfaces are in [`knowledge_project.dart`](../lib/src/model/knowledge_project.dart);
the DTOs are in [`knowledge_models.dart`](../lib/src/model/knowledge_models.dart).
Neither `KnowledgeProject` nor `KnowledgeSearchModel` has a concrete implementation here.
`KnowledgeProjectSnapshot` exposes bundles, concepts, assessed validations and one graph;
it has no complete file inventory or raw-file read operation.
Supply those operations outside this interface or evolve it before promising a complete reader.
The [file models](../lib/src/model/knowledge_files.dart) accept concepts, indexes, logs,
configuration and references, but the [tree projection](../lib/src/model/knowledge_file_tree_projection.dart)
does not discover or read them.

These absent application pieces are integration/product follow-up, not additional merge gates for the graph SDK or indexing backend.

## Bridge the graph without losing information

Core [`WayfinderProject`](../../wayfinder/lib/src/project/project_bundles.dart)
discovers bundles. Flutter `KnowledgeProject` is a separate reader interface.
Likewise, core [`WayfinderGraphResult` and `projectWayfinderGraph`](../../wayfinder/lib/src/project/graph.dart)
wrap an `OkfGraph` plus `fieldEdges`; Flutter `KnowledgeGraph` is a different DTO.
There is no automatic conversion or JSON decoder between them.
The source bundle remains authoritative: graph projection needs no search index, embedding model or inference.

Map nodes and **both** ordinary `OkfGraph.edges` and `WayfinderGraphResult.fieldEdges`:

| Core value | Flutter mapping |
| --- | --- |
| Node `id.value`, `id.documentPath`, title and type | Preserve concept ID; prefix the document path with the bundle's project-relative path |
| Edge `source.value` | `KnowledgeGraphEdge.source` |
| Resolved concept `targetConcept.value` | `KnowledgeGraphEdge.target`; do not use the written Markdown/resource target as the concept ID |
| Other target `rawTarget` | `KnowledgeGraphEdge.target` |
| Edge `resolvedPath` | Project-relative `path`, when present; prefix its bundle-relative path exactly once |
| Ordinary origin | Map explicitly: `bodyLink` → `body`; `resource`, `sourceResource`, `computation`, `executorResource`, `attesterResource` → the corresponding Flutter members |
| Resolution | Map explicitly: `resolvedConcept`, `resolvedAsset`, `external`, `descriptor`, `unresolved`, `invalid` → their corresponding Flutter members |
| Field edge `field == 'relationships'`, `name` | Origin `relationships`, relationship `name`; keep the edge even when `name` is null |

For wire input, origin strings are `body`, `resource`, `sources.resource`, `computation`,
`executor.resource`, `attester.resource`; resolutions use `resolved-concept` and `resolved-asset`
for the two resolved cases. Do not map enums by ordinal or assume Dart names equal wire values.
The [field-edge source](../../wayfinder/lib/src/field_edges.dart) defines `field`, `name`,
`targetConcept` and `resolvedPath`. Dropping field edges drops typed relationships.
Keep origin, resolution and relationship labels through projection; the scene coalesces parallel edges for display.
For example, bundle `knowledge` plus `images/map.png` becomes `knowledge/images/map.png`,
never `knowledge/knowledge/images/map.png`. Concept IDs remain bundle-relative and unchanged.

Honor the [snapshot contract](../lib/src/model/knowledge_project.dart): `snapshot` reads current
files; `concept`, `validation` and `graph` reuse that bundle's last loaded snapshot.
Keep bundle identity, concept ID and project-relative file path separate.
Invalidate the cached revision when files, binding or lock change.
Retain assessed validations; preserve core `INCOMPLETE` for absent or unresolved assessments instead of inventing `PASS`.

`projectWayfinderGraph` reloads disk on every call and filters types, paths and resolutions;
it has no focus/depth parameters. Repeated calls do not implement the snapshot contract.
An adapter can derive `OkfGraph.fromBundle` and `okfFieldEdges(bundle, wayfinderLinkFields)`
from its cached `OkfBundle`, then apply focus/depth against that graph.
`okfFieldEdges` is public through [`wayfinder.dart`](../../wayfinder/lib/wayfinder.dart);
`wayfinderLinkFields` is public through [`project.dart`](../../wayfinder/lib/project.dart).
Preserve load findings rather than presenting a refused graph as a successful empty graph.

## Own the view in the host

The [scene source](../lib/src/model/knowledge_graph_scene.dart) owns these presentation choices:

- Local scope is the default. No valid focus means an empty scene; Whole bundle is opt-in.
- Depth defaults to 1 and clamps to 1–3. Local distance follows concept edges in either direction.
- Local views suppress concept edges within one ring; concept self-links are suppressed in both scopes.
- Attachment, external/descriptor and unresolved/invalid target layers are hidden until requested.
- Concept IDs stay unchanged. Synthetic target IDs use `/<kind>:<path-or-target>`;
  this replaces the collision-prone `<kind>:...` spelling. Treat target IDs as opaque.

The leading slash keeps synthetic IDs outside valid OKF concept IDs, including IDs containing colons.
Resolve selection/open callback IDs through `scene.indexById`, then inspect the node's
`kind`, `path` and `target`. Open concepts by bundle and concept ID, files by their
project-relative path, and external targets through host navigation policy.
Do not parse synthetic IDs or use them as concept IDs.

The host owns bundle, focus, scope, depth, layers and selected ID.
Keep enough cached graph data to support Whole or a deeper local request.
When calling `layOutKnowledgeGraph` asynchronously, tag requests with the current
bundle revision/query and ignore completions superseded by newer requests or disposal.
Reuse the same `KnowledgeGraphScene` across unrelated rebuilds.
A new scene clears canvas label caches; a changed layout also refits and fades.
Layout equality lets refreshed content retain pan and zoom.

Build [`KnowledgeTypePalette`](../lib/src/graph/knowledge_type_palette.dart) from **all concepts of the bundle**,
not just visible nodes. Map findings to `attentionOf`; provide `activeId`, `onSelect`
and `onOpen`. Supply toolbar controls through the canvas state's `fit()` and `recentre()`.
The host also supplies icons, tooltips, translated labels and navigation.
Pointer/touch and screen-reader actions exist; graph keyboard navigation still needs product work.

### Existing source responsibilities

| Module | Responsibility |
| --- | --- |
| Core [project graph](../../wayfinder/lib/src/project/graph.dart) | Derived OKF graph plus relationship edges; JSON/DOT/Mermaid; no Flutter dependency |
| Flutter [models](../lib/src/model/knowledge_models.dart) / [project interface](../lib/src/model/knowledge_project.dart) | Portable values and backend contract |
| [Scene](../lib/src/model/knowledge_graph_scene.dart) | Scope/layers/rings, edge coalescing, deterministic layout, isolate dispatch and layout equality |
| [Canvas](../lib/src/graph/knowledge_graph_canvas.dart) | Widget lifecycle, fit/recentre, label measurement/cache lifecycle, gestures, hit-testing and overlay composition |
| [Painter](../lib/src/graph/knowledge_graph_painter.dart) | Painting, label collision suppression, viewport notifier and painted semantics |
| [Hover card](../lib/src/graph/knowledge_graph_hover_card.dart) / [legend](../lib/src/graph/knowledge_graph_legend.dart) | Overlay presentation |
| [Palette](../lib/src/graph/knowledge_type_palette.dart) / [labels](../lib/src/graph/knowledge_graph_labels.dart) | Bundle-stable type colors and localization seam |

Use these seams for integration. They do not require a structural rewrite or another graph service.

## Indexing and search boundaries

The [current store](../../wayfinder_embeddings/README.md#knowledge-store) already provides
saved generations, status, force indexing, progress, cancellation and ranked citations.
[Indexing PR #172](https://github.com/btwld/wayfinder/pull/172) adds portable identity and resumable
embedding checkpoints, with force starting without saved checkpoint vectors. It supplies backend work, not Flutter integration.
The following links describe **PR-only APIs**, checked at `b28a746`; they are not part of this Flutter branch:

- [`ProjectBundle.identity`](https://github.com/btwld/wayfinder/blob/b28a746a1f5858c7f34abd9a7646944f3e4ab729/packages/wayfinder/lib/src/project/project_bundles.dart):
  a host-assigned identity for relocation. Discovery still defaults to root-path identity;
  assign a unique identity per logical bundle when constructing host bundle values.
  Flutter bundle summaries have no persistent index-identity field.
- [Resumable store indexing](https://github.com/btwld/wayfinder/blob/b28a746a1f5858c7f34abd9a7646944f3e4ab729/packages/wayfinder_embeddings/lib/src/store/knowledge_store.dart):
  completed batches survive interrupted runs; force discards checkpoint reuse; publication remains atomic.
- [`StaleIndexPolicy.serve`](https://github.com/btwld/wayfinder/blob/b28a746a1f5858c7f34abd9a7646944f3e4ab729/packages/wayfinder_embeddings/lib/src/store/index_result.dart):
  permits stale published results even without a running refresh. Missing/incompatible indexes remain refused.

Choose a search stale policy explicitly. In this branch, `refuse` is the default;
`serveWhileRefreshing` allows a previous publication during refresh.
Use the PR-only `serve` policy only after integrating that backend, if offline/scheduled refresh needs it.
Preserve `sourceChanged`, freshness, notices and cancellation in the host.
Show changed-source/refresh notices beside results and verify current files before using indexed citation lines.
Search never implicitly indexes.

The [backend status/progress types](../../wayfinder_embeddings/lib/src/store/index_result.dart)
are richer than Flutter's provisional `KnowledgeIndexState` and `KnowledgeIndexProgress`:
the enum omits incompatible status and its reason; `refreshing` loses `previous`;
warnings, changed paths, progress counts and the final `WayfinderIndexResult` have no fields.
Keep the full state in the host or evolve these APIs before promising a complete indexing UX.
The [backend search result](../../wayfinder_embeddings/lib/src/store/project_search.dart)
also separates matches/context and carries inclusion reason, similarity, type and status.
Flutter hits omit those fields; Flutter notices retain only code/message, losing bundle, paths and target.
Preserve that information outside the DTOs when the UI needs it.

## Practical integration sequence

1. Choose the backend revision and target platforms. Keep #172-only APIs conditional on integrating that branch.
   The SDK is unpublished; its Flutter-only dependency does not establish native retrieval support on any platform.
2. Discover bundles with `WayfinderProject.discover` from the host's project root.
   Implement cached snapshots and reader projections, including validation and file inventory/opening.
3. Map both graph edge collections, then wire query state, stale-layout suppression, palette, attention and navigation.
   Verify the graph reader before introducing model acquisition or indexing.
4. Implement `KnowledgeSearchModel` with [`EmbeddingModelCache`](../../wayfinder_embeddings/README.md#provision-the-model-from-an-application).
   `locate` is offline; call `provision` only after consent to the exact model target.
   Reconcile Flutter consent with model identity, URL, size and SHA-256; also show the cache destination.
   Supply the verified model path to `LocalModelEncoderProvider`.
5. Own the app data/cache directory, native runtime initialization and native library/model packaging.
   Bridge Flutter cancellation to core/store/model cancellation and preserve stable backend error codes in host state.
   Own subscription cleanup, encoder/store disposal and `KnowledgeProject.close` behavior.
6. Keep all OKF bundle I/O within one process on **one isolate**, per
   [host operating boundaries](../../wayfinder/README.md#host-operating-boundaries).
   Pure graph-layout compute may use another isolate; it performs no OKF disk I/O.
7. Add the index/search controller and complete reader UI, then a runnable example.
   Verify native execution and packaging on each claimed target; existing source checks do not establish physical-device or untested-platform support.

[MCP](../../wayfinder_cli/README.md#mcp-server) shares backend services, but is not a drop-in Flutter adapter.
Its per-bundle graph wrappers need decoding and mapping; it supplies neither Flutter snapshot/focus/depth behavior
nor the interface's indexing progress stream. Choose a transport deliberately instead of treating shared domain names as type compatibility.
