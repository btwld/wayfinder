# Wayfinder SDK and Flutter editor — adjustment specification

Revision 3 · 27 September 2026  
Repository: `btwld/wayfinder`  
Reviewed baseline: `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f`  
Status: draft planning handoff. No implementation or runtime verification is implied.

The active first implementation batch is the existing [Batch A execution specification](../wayfinder-sdk-batch-a.md): **W01 → W02 → W03**. This document carries the complete architecture adjustment and links to the remaining work items. The ticket files are the authoritative acceptance checklists for each slice.

## Decision

Keep **Dart, Flutter, Super Editor, local Markdown, and OKF**.

Use **AckInfer** for shared operation contracts. Reuse the existing `okf`, `wayfinder`, and `wayfinder_embeddings` implementations. Extract a supported `wayfinder_sdk` from CLI-owned runtime behavior instead of creating a second validation or retrieval engine.

Markdown plus OKF remain the saved source of truth. Super Editor is only the visual editing surface. Search indexes and editor document models are derived state.

## Package ownership

| Owner | Responsibility |
| --- | --- |
| `okf` | Existing OKF document semantics, bundle inspection, specification validation, graph values, and generic change machinery. |
| `wayfinder` | Concepta Profile rules and partitioned Profile/OKF validation. Candidate validation belongs here. |
| `wayfinder_embeddings` | Chunking, BM25/dense/hybrid retrieval, snapshots, synchronization, stores, and encoders. |
| new `wayfinder_sdk` | Shared typed operation contracts, runtime coordination, resource ownership, failures, and later revision/session policies. |
| `wayfinder_cli` | CLI arguments, text/JSON presentation, exit mapping, MCP registration, executable-specific discovery, install/update behavior. |
| Flutter app | Super Editor, source editor, unsaved sessions, byte-preserving patches, recovery, workspace UI, and commands. |

The SDK must be a deep module, not a pass-through façade. It must not depend on Flutter or MCP. Do not generate parallel SDK versions of existing OKF graph, document, metadata, or finding types.

## AckInfer

Start with the existing search request. Preserve its nonblank query rule, limit range **1–100**, and default **5**. Characterize omitted values, explicit null, unknown keys, Unicode whitespace, and wrong types before changing code.

Use real Ack generation. Do not hand-write generated output. Extend repository generation checks so a second clean generation produces no drift. Generated constructors are not themselves a validation guarantee; public operations still validate directly constructed values.

Use generation for SDK-owned request/control records. Do not use generated JSON models as the authority for arbitrary Markdown frontmatter.

## Validation

Keep three modes distinct:

1. plain Markdown;
2. generic OKF;
3. OKF with the declared Concepta Profile.

The editor must not require a Profile to open or save a folder.

Batch B adds candidate validation for unsaved source without writing it to disk. Equivalent in-memory and on-disk candidates should share the same owning rules where the checks are equivalent. Results must distinguish loader failures, OKF findings, Profile findings, unsupported releases, and judgment rules that remain unassessed.

## Search runtime

Batch A preserves current search mode, freshness refusal, locking, resource lifetime, and generation publication behavior.

Later work introduces explicit session ownership and revision-aware search. One writer builds a private generation. Readers may pin only completed generations. The default SDK policy remains current-only; an explicit last-completed policy may serve stale results with generation/revision metadata and a clear notice.

No reader may observe a partly published or deleted generation. Cleanup must be safe across processes, not only within one isolate. Citations belong to the indexed revision; current-file navigation must detect divergence.

Basic path/title lookup must not depend on semantic indexing. Do not add a second primary search database merely to preserve an earlier sketch.

## Saving versus structured authoring

A **source save** protects user work. It may save incomplete or nonconformant source and report diagnostics. It does not silently regenerate indexes or append a knowledge log.

A **structured bundle change** is stronger: prepare the exact candidate, apply the correct navigation/log projection, validate that candidate, show the diff, and commit only if the source revisions still match.

Issue #45 records the generic-OKF versus Concepta projection mismatch. Resolve that narrow ownership decision before Profile-aware structured authoring. Prefer reuse of the generic writer plus a proven extension seam over duplicated transaction machinery.

## Source preservation and editor safety

The Flutter application must retain original bytes, raw frontmatter, line-ending policy, and the saved baseline.

- No edit means no rewrite.
- Body-only edits preserve untouched frontmatter.
- Metadata-only edits preserve untouched body source.
- Unsupported Markdown remains source-editable.
- Mode switching alone never saves.
- Only one representation is editable at a time.
- A failed visual conversion preserves both original and current work.
- An older save completion cannot clear newer unsaved edits.
- External file changes conflict with dirty local edits instead of overwriting them.
- Recovery data is separate from disposable search data.

Workspace-relative paths must be canonicalized. Symlink behavior must be explicit. Rendering Markdown must not execute HTML/code, fetch remote resources, or follow arbitrary URI schemes by default.

## Optional native split and capture

Do not claim model-free execution removes native package dependencies. First measure the actual dependency and asset graph from an independent consumer. Split native retrieval packaging only if a concrete distribution requirement justifies it.

Capture/import remains optional. A future capture workflow preserves original evidence, hashes and provenance, extracts located text, reports warnings, and promotes only reviewed changes into knowledge. Raw captures do not enter normal search or become verified automatically. ADR-0013 remains a proposal, not a shipped extraction interface.

## Delivery sequence

| ID | Deliverable | Blocked by | State |
| --- | --- | --- | --- |
| [W01](tickets/W01-typed-search-request.md) | AckInfer search request | None | Batch A |
| [W02](tickets/W02-extract-sdk.md) | Supported `wayfinder_sdk` | W01 | Batch A |
| [W03](tickets/W03-verify-sdk-batch.md) | Regeneration, external-consumer, and review evidence | W02 | Batch A gate |
| [W04](tickets/W04-candidate-validation.md) | Unsaved candidate validation | W02 | Batch B |
| [W05](tickets/W05-retrieval-session.md) | Explicit retrieval session ownership | W03 | Batch B |
| [W06](tickets/W06-search-during-refresh.md) | Revision-aware search during refresh | W05 | Batch B; #110 |
| [W07](tickets/W07-profile-authoring.md) | Reviewed Profile-aware authoring | W04 | Batch B; #45 |
| [F01](tickets/F01-source-workflow.md) | Safe local source open/edit/save | W03, W04 | Batch C; app repo required |
| [F02](tickets/F02-super-editor-workflow.md) | Bounded Super Editor workflow | F01 | Batch C |
| [F03](tickets/F03-editor-search-inspector.md) | Search/diagnostics/related-document inspector | F02, W06 | Batch C |
| [X01](tickets/X01-native-dependency-option.md) | Optional lightweight packaging split | W03 | deferred |
| [X02](tickets/X02-reviewed-capture.md) | Optional reviewed capture/import | F01, W07 | deferred |

Only W01–W03 are authorized for the first implementation session. Do not silently continue into Batch B.

## Verification and review

Use the highest practical public seam. Preserve the existing CLI and MCP wire contracts during Batch A.

Required evidence includes:

- before/after input compatibility;
- representative CLI and MCP compatibility;
- real generator output and clean second generation;
- public SDK consumption outside monorepo resolution;
- source non-mutation;
- resource close/failure behavior;
- explicit native-test outcomes;
- no unintended ObjectBox schema/model-ID changes.

At the end of Batch A, review the fixed base/head on two axes:

**Standards:** repository instructions, ownership, dependency direction, public/private imports, duplication, resource lifetime, generated files, native packaging, and speculative abstractions.

**Spec:** every W01–W03 acceptance criterion, wire compatibility, source non-mutation, generator stability, package consumption, and scope creep.

Use [REVIEW.md](REVIEW.md) and record evidence in [IMPLEMENTATION_REPORT_TEMPLATE.md](IMPLEMENTATION_REPORT_TEMPLATE.md). A self-review must be labeled self-review. Missing or skipped checks remain missing or skipped.

## Out of scope

The planning PR does not implement the SDK or editor. It does not publish packages, merge code, change real knowledge bundles, close #110/#45, add a graph UI, create a sync/collaboration backend, add a generic Profile platform, or create the Flutter application repository.

See [STATUS.md](STATUS.md) for actual execution state and [task-manifest.json](task-manifest.json) for the machine-readable dependency graph.
