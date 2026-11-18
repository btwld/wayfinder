# Architecture decision log

Accepted choices and their trade-offs; each date is the original decision or
named amendment date. Earlier wording remains in Git history. Existing ADR IDs
are retained for navigation; add future decisions here under titled entries,
without new numbered files. Use 1–3 sentences: what, why and cost.

[README core concepts](README.md#core-concepts) describe the current model.
The [engine contract and schemas](implementation/README.md) govern exact behavior;
[contribution requirements](docs/contributing.md) govern contract/Profile changes.
Specs, API references and runbooks stay separate from this log.

## Local embeddings with Arctic XS (ADR-0009)

Date: 2026-09-09.

Use verified local Arctic Embed XS Q8_0 weights: in [synthetic comparisons](packages/wayfinder_embeddings/fixtures/README.md), XS matched larger Q8 models on 50 of 60 first-context judgments with lower per-query cost, supporting a size/cost choice rather than a general accuracy claim.
Local inference costs model download, startup and disk space; omitting footnote definitions beside ordinary body passages reduces citation competition but can miss useful support, so reviewed regressions or independent-corpus gains should trigger reconsideration.
Retrieval modes were replaced by ADR-0017; model/input identity remains [pinned separately](packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart).

## Explicit local CLI operations (ADR-0010)

Date: 2026-09-09; dense-only amendment 2026-10-18; encoder/output update 2026-10-20.

Provide one CLI for validation, explicit indexing and cited search so retrieval remains inspectable and separate from Profile conformance; runtime commands never download/train models or implicitly rebuild indexes.
This requires users to reindex after edits and retain derived local copies of bundle text; ADR-0022 replaces the original ObjectBox storage and permits previous snapshots during refresh, while [the CLI guide](packages/wayfinder_cli/README.md) owns current commands.

## Local MCP over shared services (ADR-0011)

Date: 2026-09-09; project-wide discovery 2026-10-16; encoder/output update 2026-10-20.

Expose validate/index/search/graph over local MCP stdio using the CLI's services, because agents need typed discovery/results without implementing another gate or search; default discovery spans project bundles, with an explicit single-bundle override.
Deferring HTTP/authentication and authoring tools keeps the boundary small, but hosts own approval and lifecycle, and per-bundle indexing cannot roll back an earlier publication when a later bundle fails.
[Transport and cancellation details](packages/wayfinder_cli/README.md#mcp-server) remain operational guidance; ADR-0022 governs refresh reads.

## Project the ordinary OKF graph (ADR-0012, ADR-0021)

Date: 2026-09-11; typed edges 2026-10-01; library relocation 2026-10-24.

Project the ordinary OKF graph and add typed relationships beside it, avoiding a competing graph model while exposing the loaded graph to CLI/MCP and embedded hosts.
The projection and `wayfinderLinkFields` live in the project library (ADR-0021), with Profile-agnostic field-list injection into graph/retrieval; this graph is discardable, and consumers needing different semantics must seek a compatibility review rather than treating it as a new source of truth.
[Graph output](packages/wayfinder_cli/README.md) remains okf JSON/Mermaid/DOT plus relationship edges.

## Exact queries over live concepts

Date: 2026-10-31.

Add read-only structured queries to the core project library and share their contract through CLI/MCP, so reusable metadata views need neither a per-project renderer script nor semantic ranking. Saved query IDs resolve versioned local JSON in the consuming project's `.wayfinder/queries/`; the existing metadata predicate remains available to embeddings consumers, and no OKF/Profile semantics change. Every query scans/fingerprints live sources and refuses partial data, paying filesystem cost without promising a transactional snapshot or computation attestation; see [queries](docs/queries.md).

## Dense-only retrieval (ADR-0017)

Date: 2026-10-18.

Use dense retrieval throughout actual library, CLI/MCP and evaluation searches, removing lexical/hybrid modes and implicit fallback to reduce maintained APIs, fixtures and command contracts; this is a product/maintenance choice, not proof that dense is universally better.
Consumers must supply an embedder and migrate retired arguments, while preview/parsing remain model-free, compatible snapshots remain usable and model failures stay errors.
The [migration/evaluation guide](packages/wayfinder_embeddings/README.md#dense-only-migration) retains generic reranking/context policy and historical evidence attribution; another method needs a concrete need and reviewed quality/cost evidence.

## Embeddable libraries and host ownership (ADR-0018, ADR-0023)

Date: 2026-10-22; host resolution controls 2026-10-24.

Expose project and retrieval behavior as public libraries so IDE/agent hosts need no CLI internals, with injected resources, bounded project roots, typed failures, hardened origin-only Git and checked skill paths (ADR-0023).
Hosts pay for resource lifecycle, fetch consent and serialization: all okf bundle I/O in one process stays on one isolate because its process-owned locks do not exclude isolates, while Wayfinder uses descriptor-owned locks on local disk.
Package parsing normally has a ten-second isolate bound but falls back to unbounded synchronous parsing when spawning fails; hosts needing hard bounds must isolate work themselves, as detailed in [host operating boundaries](packages/wayfinder/README.md#host-operating-boundaries).

## Safe writes with a delta gate (ADR-0019, ADR-0024, ADR-0025)

Date: 2026-10-22; empty commits and shared assessor 2026-10-24.

Keep one prepare/assess/commit path through okf's projection seam, because raw host edits bypassed Profile-generated indexes and caller-authored history; rewrite only indexes whose generated text changes and reject stale bundle/configuration inputs, even for empty commits (ADR-0024).
The whole candidate must pass OKF, but Profile acceptance is a delta with no introduced errors: old errors or an unassessed Profile may remain, so callers needing conformance still require the full gate and may move the shared assessor to a bounded isolate (ADR-0025).
Hosts must serialize relock/get with writes because no lock spans both checks; canonical serialization, leftover lock files and possible rollback failure are costs described in the [authoring API](packages/wayfinder/README.md#authoring).

## Adoption as plan then apply (ADR-0020, ADR-0024, ADR-0025)

Date: 2026-10-22; offline relock and host seams 2026-10-24.

Provide a previewable plan then guarded apply for hosts, approving each fetched source, binding the package's declared id, digesting host inputs and sharing the assessor; offline relock reuses pinned commits without Git or skill writes (ADR-0024/0025).
Planning may populate the external cache, but applying refuses stale/conflicting inputs and holds the project lock across owned writes/undo; failed steps roll back where possible, host writes require host-managed cleanup, and final validation runs after unlock without undoing applied files.
Adoption therefore can remain incomplete after a failed final gate, and existing bindings remain migration work; [adoption API/seeds](packages/wayfinder/README.md#adoption) keep agent configuration and invented concepts outside the library's ownership.

## Immutable plain-file index generations (ADR-0022, ADR-0026)

Date: 2026-10-24; model lookup correction 2026-10-26.

Replace application ObjectBox indexes with immutable snapshot/vector generations and an atomically replaced current pointer so readers can use the previous publication during refresh without a writer lock; the old HNSW index was unused, so exhaustive scoring preserves ranking behavior.
Search exposes refresh/source-change notices and refuses stale snapshots outside refresh, while every index/prune collects expired generations (ADR-0026); duplicate storage during staging, rebuilds on upgrade, deferred Windows deletion and filesystem-dependent locking remain costs.
[Storage and source notices](packages/wayfinder_cli/README.md#local-storage) remain operational docs, and [model lookup](packages/wayfinder_cli/README.md#embedding-model-lookup) uses explicit override, installed bundle, working/source development models, then verified cache, correcting ADR-0026's former order.

## Prepared 0.5 compatibility and release evidence

Date: 2026-10-26; amended 2026-11-05.

Define the prepared public surfaces and compatibility obligations in the [0.5 contract](docs/stability.md), because embedders and machine consumers need an explicit boundary across independently versioned packages; public breaking changes carry breaking releases (the next 0.x minor) and migration notes, while Profile releases remain independent. The packages stay on 0.x, so the unpublished 1.0.0 became 0.5.0 with the same obligations.
Require successful source CI from the exact commit's push to main and independent hosted CLI resolution before release eligibility, because a green PR or workspace resolution cannot establish those facts; the [read-only preflight and remaining distribution gates](docs/releasing.md#release-preflight) can therefore stay blocked on unpublished siblings or missing main evidence without declaring failed candidate code.

## Bounded adoption paths and process cleanup

Date: 2026-11-04.

Refuse parent segments and any-case `.git` segments at the adoption request boundary, for the bundle, host inputs and seed concepts, before preparing writes, because normalized aliases hid unsafe intent. Freeze Git's root through termination and discover descendants until the frozen tree stops growing within one inspection budget. A failed listing kills those verified descendants with the root and resumes only non-root ids whose parentage no longer matches. POSIX PID operations remain best effort because they are not atomic process handles.

## Retrieval source decisions and bounded ingestion

Date: 2026-11-04.

Carry the shared resolver's source decisions from the snapshot into search Markdown so displayed paths agree with `unresolved-source` notices. Attribute encoder failure at its own calls, including a returned vector with the wrong dimension or a non-finite component, and decode freshness through the loader's UTF-8 rules, preserving healthy models when bundle I/O fails; ingestion uses digest validation and a temporary spool to bound retained text, while keeping store-batch atomicity rather than promising call-wide rollback.

## Flutter reader SDK outside the Dart workspace

Date: 2026-11-03.

Keep Flutter reader models and widgets in `packages/wayfinder_flutter`, free of any design kit, so desktop and phone readers share one implementation while hosts keep sign-in, storage, navigation and chrome.
The package stays out of the pub workspace and root analysis so that CLI and library contributors need no Flutter SDK; the cost is a separate workflow and dependency resolution for it.

## Ack 2, analyzer 13 and ObjectBox 6 preview

Date: 2026-11-05.

Adopt Ack 2 and analyzer 13 for host dependency compatibility. Supporting analyzer 13 in this workspace also moves the ObjectBox generator and its paired Dart and native runtime to 6 preview/beta. This accepts prerelease risk and requires ObjectBox 5 consumers to upgrade, while CLI knowledge indexes keep using plain-file generations. Exit: move the override, installer and manifest to the first stable ObjectBox 6 release, keeping every entity id and UID.

## Consolidated knowledge entries and model-free reader backends

Date: 2026-11-07; consolidated 2026-11-09.

Keep portable retained values, memory capture and lease mechanics behind core's browser-closed `knowledge.dart`, and native bounded read-only filesystem browsing behind `project.dart`, because import closures provide the platform boundary without two extra unpublished packages. Flutter owns widgets/controllers and preference/finding presentation; reader regression tests live in core and the portable closure is checked transitively in CI. The unpublished snapshot-validation conversion and capture-time external observations leave this change because they have no production caller; raw reads, byte revisions, grant/lifecycle safety, shared file classification and the native validator's optional external-lookup callback remain, with no Profile/OKF policy migration.

## Desktop browsing maintenance

Date: 2026-11-09.

For #180's desktop caller, reject file/symbolic project roots at open and exclude every dot-prefixed browsing entry before inspection, removing the unused hidden-entry option and finding-source field without changing OKF inventories or conformance. Native validation reserves `memory:` and authority-bearing `scheme://` roots for URI inputs, treating other colon-containing names as filesystem paths to avoid conflating POSIX names with URI schemes. Keep idle capture reuse until close because the host closes projects on worktree changes, accepting the retained capture and two-scan peak allocation.

## Bounded document capture with attachment inventory

Date: 2026-11-10.

For the desktop reader's real attachment-heavy repository (4 MB knowledge plus
154 MB captures under a 32 MB capture budget), capture only classified Markdown
and project configuration/lock bytes, failing capture if either present input
cannot fit; inventory attachments and over-budget documents with size, modification
instant and per-file refusals. Share file identity between manifests and revisions,
excluding per-file refusal wording. Keep exact retained-byte reads
and metadata-only revisions for omitted files, refusing their reads and any
incomplete bundle graph; the cost is inventory-only attachments and inability
to detect their same-size/restored-mtime edits, with no OKF/Profile change.
