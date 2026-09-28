# Wayfinder SDK and Flutter editor — adjustment specification

Revision 5 · 27 September 2026  
Repository: `btwld/wayfinder`  
Reviewed baseline: `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f`  
Status: draft planning handoff. No implementation or runtime verification is implied.

The active first implementation batch is the existing [Batch A execution specification](../wayfinder-sdk-batch-a.md): **W01 → W02 → W03**. This document carries the complete architecture adjustment and links to the remaining work items. The ticket files are the authoritative acceptance checklists for each slice.

## Decision

Keep **Dart, Flutter, Super Editor, local Markdown, and OKF**.

Use **AckInfer** for shared operation contracts. Reuse the existing `okf`, `wayfinder`, and `wayfinder_embeddings` implementations. Extract a supported `wayfinder_sdk` from CLI-owned runtime behavior instead of creating a second validation or retrieval engine.

Markdown plus OKF remain the saved source of truth. Super Editor is only the visual editing surface. Search indexes and editor document models are derived state.

For the early companion app, use Remix's Vanilla `dashboard_shell` recipe and make Wayfinder search, concept-type filtering, validation, and index/passage inspection part of the first complete searchable workbench. The read-only bootstrap remains smaller. See [WORKBENCH.md](WORKBENCH.md) for the reviewed template, runtime evidence, and acceptance details. This does not delay search until Super Editor or expand Batch A's extraction scope.

[Filters and diffs](FILTERS_AND_DIFFS.md) defines visible applied filters, truthful counts, and an optional read-only local Git Changes destination. Use existing Remix controls and a native source-diff view. Git is not required for browsing, validation, or search. WB03 is independent of WB02 and adds no repository-write commands.

## Package ownership

| Owner | Responsibility |
| --- | --- |
| `okf` | Existing OKF document semantics, bundle inspection, specification validation, graph values, and generic change machinery. |
| `wayfinder` | Concepta Profile rules and partitioned Profile/OKF validation. Candidate validation belongs here. |
| `wayfinder_embeddings` | Chunking, BM25/dense/hybrid retrieval, snapshots, synchronization, stores, and encoders. |
| new `wayfinder_sdk` | Shared typed operation contracts, runtime coordination, resource ownership, failures, and later revision/session policies. |
| `wayfinder_cli` | CLI arguments, text/JSON presentation, exit mapping, MCP registration, executable-specific discovery, install/update behavior. |
| Flutter app | Super Editor, source editor, unsaved sessions, byte-preserving patches, recovery, workspace UI, commands, and optional local Git review. |

The SDK must be a deep module, not a pass-through facade. It must not depend on Flutter or MCP. Do not generate parallel SDK versions of existing OKF graph, document, metadata, or finding types. Keep the local Git adapter inside the app until another real consumer justifies extraction.

## AckInfer

Start with the existing search request. Preserve its nonblank query rule, limit range **1–100**, and default **5**. Characterize omitted values, explicit null, unknown keys, Unicode whitespace, and wrong types before changing code.

Use real Ack generation. Do not hand-write generated output. Extend repository generation checks so a second clean generation produces no drift. Generated constructors are not themselves a validation guarantee; public operations still validate directly constructed values.

Use generation for SDK-owned request/control records, not arbitrary Markdown frontmatter. W08 introduces a separate filtered-search/inspection contract after W03; it must not silently alter W01's CLI/MCP schema. Reuse actual upstream values and do not invent a second schema for transient UI state.

## Validation

Keep three modes distinct:

1. plain Markdown;
2. generic OKF;
3. OKF with the declared Concepta Profile.

The editor must not require a Profile to open or save a folder.

Batch B adds candidate validation for unsaved source without writing it to disk. Equivalent in-memory and on-disk candidates should share the same owning rules where the checks are equivalent. Results must distinguish loader failures, OKF findings, Profile findings, unsupported releases, and judgment rules that remain unassessed.

Presentation filters never change the full validation verdict. Display full error/advisory totals alongside shown counts, and never label a filtered-empty list as an automated pass. Pending source changes invalidate the report's currentness, not its historical identity.

## Search runtime

Batch A preserves current search mode, freshness refusal, locking, resource lifetime, and generation publication behavior.

Later work introduces explicit session ownership and revision-aware search. One writer builds a private generation. Readers may pin only completed generations. The default SDK policy remains current-only with respect to source freshness; an explicit last-completed policy may serve stale results with generation/revision metadata and a clear notice. This freshness policy is different from concept lifecycle filtering.

No reader may observe a partly published or deleted generation. Cleanup must be safe across processes, not only within one isolate. Citations belong to the indexed revision; current-file navigation must detect divergence.

Basic path/title lookup must not depend on semantic indexing. Do not add a second primary search database merely to preserve an earlier sketch.

W08 reuses existing lower-level concept-type/path eligibility before ranking and exposes bounded read-only index/passage inspection through the supported SDK. Keep dense contextual search with relationship expansion as the default. BM25/hybrid comparison is explicit and not evidence of superior relevance without a fixed evaluation. Separate concept types from chunk kinds, matches from related context, and scores from confidence.

Expose the effective applied policy and source generation. Use OR within one filter category and AND between categories, with empty selections unrestricted. Counts identify their population; top-k matches are not total corpus matches. Keep pending UI filter edits separate from results of a previous submission. Do not restore restricted documents silently through related-context expansion.

The initial workbench respects existing busy/stale refusals. It does not require W06 or bypass its locks. W05/W06 improvements, when present, remain the single owning lifecycle implementation. The app never parses index storage files or embeds documents through a duplicate runtime.

## Saving versus structured authoring

A **source save** protects user work. It may save incomplete or nonconformant source and report diagnostics. It does not silently regenerate indexes or append a knowledge log.

A **structured bundle change** is stronger: prepare the exact candidate, apply the correct navigation/log projection, validate that candidate, show the diff, and commit only if the source revisions still match.

Issue #45 records the generic-OKF versus Concepta projection mismatch. Resolve that narrow ownership decision before Profile-aware structured authoring. Prefer reuse of the generic writer plus a proven extension seam over duplicated transaction machinery.

A read-only Git review is neither kind of write. Refreshing or viewing Changes must not stage, commit, apply, restore, or modify any repository source, staging index, ref, or configuration. Keep Git's staging index distinct from the Wayfinder search index.

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

## Read-only changes and diff visibility

Name both comparison sides: HEAD to staging index, staging index to saved working tree, absent to untracked file, saved baseline to unsaved buffer, or indexed source to current file. Enable later comparison kinds only when their actual source providers exist. A search snapshot is not HEAD; a buffer is not a saved file.

Use a native unified source diff first, with old/new line numbers, correct hunks, selectable text, final-newline markers, and explicit partial/large/binary states. Reuse the comparison model for a later side-by-side layout. Whitespace-ignore is off by default. Rendered Markdown and parsed metadata summaries cannot replace the raw diff authority.

Use the local Git executable through a small read-only process adapter with literal scoped paths, NUL-delimited machine output, controlled environment, bounded streams/timeouts, and tested external-helper policy. A read-only command is not a hostile-repository sandbox. Missing Git, unsupported filters, or unsafe repository access must not break non-Git features or cause writes/downloads. Full safety and package findings are in the companion plan.

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
| [W08](tickets/W08-filtered-search-inspection.md) | Filtered search and bounded public inspection | W03 | Workbench; planned |
| [WB01](tickets/WB01-shell-and-validation.md) | Remix dashboard shell and folder validation | None | Workbench; planned |
| [WB02](tickets/WB02-search-and-inspection.md) | Search by type, inspect index/passages, open sources | WB01, W08 | Workbench; planned |
| [WB03](tickets/WB03-git-changes-and-diffs.md) | Filter local Git changes and read labeled source diffs | WB01 | Workbench; planned |
| [F01](tickets/F01-source-workflow.md) | Safe local source open/edit/save | W03, W04 | Batch C; app repo required |
| [F02](tickets/F02-super-editor-workflow.md) | Bounded Super Editor workflow | F01 | Batch C |
| [F03](tickets/F03-editor-search-inspector.md) | Editing/concurrent-search integration using shared retrieval | F02, W06 | Batch C |
| [X01](tickets/X01-native-dependency-option.md) | Optional lightweight packaging split | W03 | deferred |
| [X02](tickets/X02-reviewed-capture.md) | Optional reviewed capture/import | F01, W07 | deferred |

Only W01–W03 are authorized for the first assigned implementation session. New workbench items are planned, not automatically executed. WB01 can bootstrap without the SDK; WB02 completes the initial searchable workbench without requiring F02 or W06. WB03 branches from WB01 independently and keeps Git optional. F03 remains later editing integration and must not create a second retrieval engine.

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

The workbench adds template-reuse, filter-before-limit, concept/chunk distinction, snapshot-citation, missing-runtime, nonblocking UI, and privacy acceptance. A type filter cannot merely remove items from an already limited result list. Mode comparison is not a quality benchmark without fixed judgments.

WB03 adds staged/unstaged separation, comparison-side identity, NUL path parsing, containment, helper-policy, diff completeness, and source/staging-index/ref/config non-mutation checks. Synthetic Git CLI checks are not Flutter/adapter verification. Hidden files or filtered findings are never implied to be reviewed or valid.

Use [REVIEW.md](REVIEW.md) and record evidence in [IMPLEMENTATION_REPORT_TEMPLATE.md](IMPLEMENTATION_REPORT_TEMPLATE.md). A self-review must be labeled self-review. Missing or skipped checks remain missing or skipped.

## Out of scope

The planning PR does not implement the SDK or editor. It does not publish packages, merge code, change real knowledge bundles, close #110/#45, add a graph UI, create a sync/collaboration backend, add a generic Profile platform, or create another application repository. The proposed workbench package in this repository is still only a plan. Local Git review does not add repository write operations or remote access.

See [STATUS.md](STATUS.md) for actual execution state and [task-manifest.json](task-manifest.json) for the machine-readable dependency graph.
