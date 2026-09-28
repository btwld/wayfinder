# Wayfinder Workbench — dashboard shell, search, and inspection

Revision 5 · 27 September 2026 · draft plan, not a runnable app.

Wayfinder source baseline: `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f`.
Planning baseline before this revision: `6bb3096f711a32f0486c7002301188ebf71023ac`.
Remix source baseline: `ca0ed4e9173f4fb12f2def558922438a03c877ca`.
Promoted Remix registry inspected: `849dbc0c03348f13f8a99bb50bebd3b0e1321012`.

## Decision and scope change

Use Remix's existing `dashboard_shell` recipe with the Vanilla preset. Make Wayfinder search, concept-type filtering, and passage/embedding inspection part of the first complete searchable workbench, not an optional debugging add-on after the editor.

The complete searchable workflow is:

**Open folder → browse and validate → build or refresh the search index → search → filter by concept type → inspect a matched passage and its source.**

Deliver a smaller read-only shell first, but do not label that intermediate slice the complete searchable workbench. Super Editor remains selected for later visual editing. Search does not wait for visual editing, concurrent indexing, or Profile-aware writes.

Revision 4 added WB01 (shell and validation), W08 (public filtered search and inspection), and WB02 (searchable workbench). Revision 5 strengthens applied-filter visibility and adds WB03, a read-only local Git Changes page. The detailed filter, comparison, rendering, process-safety, and package decisions are in [FILTERS_AND_DIFFS.md](FILTERS_AND_DIFFS.md). Git is optional and does not gate the searchable workflow.

These are planned work items, not implementations. The active SDK extraction assignment remains W01–W03. No Profile rules or existing CLI/MCP defaults change through this plan.

## What already exists, and what does not

| Capability | Evidence at the reviewed revision | Plan |
| --- | --- | --- |
| Dashboard layout | The promoted Vanilla registry includes `dashboard_shell`; its dependencies are theme, icons, icon button, sidebar, sidebar layout, and text field. [R1] | Install the shell, not `dashboard_demo` or the whole showcase. |
| Host-owned navigation | The shell takes sections, selection, body, brand, header actions, and optional search/account slots. [R2] | Use real destinations; omit account UI. |
| Wayfinder search | The CLI runtime opens a completed snapshot/store, selects dense retrieval with contextual inputs and relationship expansion, and refuses stale indexes. [W1] | Preserve this default through the public SDK. |
| Other retrieval modes | `KnowledgeIndex` exposes BM25, dense, and hybrid; `KnowledgeSearchPolicy` includes concept types, path prefixes, lifecycle selection, and relationship expansion. [W2] | Reuse the library; no new search engine. Expose supported options through a separate post-extraction SDK contract. |
| Search results | Matches, selected context, and notices are separate; CLI/MCP output includes chunks, similarity, context reasons, and via-path values. [W2, W3] | Keep these distinctions in the interface. |
| Filtered CLI request | The inspected runtime search entry accepts bundle, query, and limit, not all lower-level policy controls. [W1] | W08 is new work. Do not claim current CLI flags or SDK methods already support the proposed UI. |
| Embedding descriptor | The pinned model is Arctic Embed XS Q8_0, 384 dimensions, with a 512-token input limit. [W4] | Display values from the active descriptor; do not hard-code them into widgets. |
| Detailed index inspection | Current public command output is not a complete status, facet, and passage-inspection interface. | Add a bounded read-only SDK view. The app must not read ObjectBox files or CLI private implementation directly. |
| Git review | No Changes feature is implemented by this planning PR. | WB03 adds an optional local reader and native source diff; it is not a new Wayfinder search mode. |

No quality winner is established by this review. Dense, BM25, and hybrid can behave differently on a corpus. The default is chosen for consistency with Wayfinder, not an unsupported claim that it is always more accurate.

## Remix setup

Retain `remix 1.0.0-beta.10` as the previously verified starting runtime pin. The version-specific pub.dev page identified beta.10, while the cached version list showed beta.9 during the prior review. Recheck the package resolver before implementation; this dated review is not a permanent latest-version claim. [R3]

Use the source-pinned `remix_cli` setup from the reviewed repository until hosted publication is verified. Its inspected source requires Dart 3.12; Remix runtime has a lower Dart 3.11 / Flutter 3.41 floor. Select and test the actual Flutter toolchain, runtime dependencies, and generators together. [R4, R5]

Proposed bootstrap after resolving that toolchain:

```sh
dart run remix_cli:remix init --prefix Ui --preset vanilla
dart run remix_cli:remix registry update @remix --ref 849dbc0c03348f13f8a99bb50bebd3b0e1321012
dart run remix_cli:remix add dashboard_shell button tabs badge spinner divider select data_list
```

This is a proposed command sequence, not a command run in this review. Verify all named items at the pinned registry. A CLI pin and a registry pin are separate controls. Commit `remix.yaml`, the application lockfile, installed recipes, and the real generated adapters. Read installed constructors rather than guessing API names. Preserve notices and audit the resolved dependencies, including the shell's icon dependency. Add checkbox/popover controls only when their actual filter workflow needs them.

Use the resulting `UiDashboardShell` under `UiThemeScope`, with the theme above the Navigator/Overlay. The shell is editable application source, not a new design-system package. Keep its responsive sidebar behavior and preset tokens. Do not install sample records, charts, AI chat, account/billing screens, or unrelated Agent surfaces from `dashboard_demo`.

The shell's optional search hook only reports text changes. Initially keep the controlled query field and explicit Search action inside the Search destination. Omit the shell search slot rather than show a second unsynchronized field. The shell does not own Wayfinder queries, state, filters, or routing.

## Destinations, one folder

| Destination | Purpose |
| --- | --- |
| Library | File tree, filename/path filter, source/preview, and read-only document metadata. |
| Search | Query, concept-type and path filters, ranked passages, and selected-result inspection. |
| Validation | Auto/OKF/Concepta scope, saved-file validation, findings, and original structured reports. |
| Index | Refresh Search Index, completed-generation status, model/store information, and passage inspection. |
| Changes | Optional local Git change list, visible status/path filters, and explicitly labeled source comparisons. |

Header: selected root, Open Folder, relevant action, and appearance control. Keep an expandable Debug panel for operation details. No statistics dashboard or permanent graph canvas. Changes is introduced through WB03; earlier builds may omit it. Git missing/non-repository/policy-blocked states must not disable the other destinations.

Within Search, use a result list and a detail pane. On a narrow window, open the selected detail as a page and preserve Back state. Result selection must preserve query, filters, scroll position, and source revision. Use the existing theme for the shell and map its text/colors explicitly into the source viewer and later Super Editor.

## Folder, source, and validation rules

The selected root is explicit. Suggest an immediate `knowledge/` folder when helpful; never silently switch the root or scan unrelated folders. Raw captures are not automatically OKF concepts. Keep plain Markdown and broken YAML readable even when bundle validation or semantic indexing fails.

Auto validation uses the declared Profile when present; malformed or unsupported declarations remain visible instead of silently becoming an OKF-only pass. Preserve the owning library's errors, advisories, unsupported state, and unassessed judgment rules. Automated pass is not complete Profile conformance.

Validate Saved Files means exactly that. Later unsaved editing remains excluded unless W04 candidate validation is explicitly selected. Never save merely to validate. Navigate findings to returned locations only; path-only findings have no invented line number.

Tag every operation with root and request generation. Folder changes or newer requests invalidate older UI completions. Mark results outdated on observed source changes. Do not claim an atomic validation snapshot unless the actual inspected input set was fixed.

No source-tree writes are allowed in the read-only workbench. Index updates write only derived application data outside the selected bundle. Do not regenerate `index.md`, append `log.md`, normalize frontmatter, or change lifecycle status while browsing, searching, validating, or inspecting.

Validation filters only change presentation. Keep the full report's verdict and total errors/advisories visible alongside the filtered count. An empty filtered list is not a validation pass.

## Search behavior

### Default

Use the shared SDK implementation of Wayfinder's dense search, contextual inputs, relationship expansion, and existing default limit of 5. Preserve current CLI/MCP wire behavior. Label this mode **Wayfinder semantic search**. The Library filename/path filter remains a separate, model-free navigation feature, not semantic search under another label.

Use explicit submit initially. Typing updates local query state; it must not reload a model on every keystroke. Indexing is explicit. Folder opening, filtering, and searching must not trigger hidden model downloads, rebuilding, or external requests.

### Types and filters

**Concept type** is the OKF document metadata `type`, such as a project-defined type. Populate available values from the selected bundle's parsed concepts or the matching indexed snapshot, with the source/revision labeled. Keep unknown strings and their spelling. Do not impose a closed enum, fixed taxonomy, or infer a type from a directory. Invalid documents remain visible in Library and Validation.

**Chunk type** is a retrieval segment kind, such as paragraph, code, or table. **Content type** identifies the source format, such as Markdown. Show these separately in details. The first search filter is concept type; do not pass a chunk type into `KnowledgeSearchPolicy.conceptTypes`. Chunk-kind passage inspection is a separate bounded snapshot operation; it does not change the normal search result contract.

Apply concept-type and path-prefix eligibility before ranking in the retrieval layer, then rank and limit. Never filter the first five UI results and pretend this is a complete typed search. Empty type selection means all eligible types. Facet counts, when shown, count distinct concepts in the labeled corpus, not chunks or just the returned top results. Missing counts remain unavailable, not zero.

Keep all lifecycle states eligible by default, matching Wayfinder. Optional lifecycle/current-only controls are advanced and must use supported policy values. An explicit as-of instant is required for current-only policy. Do not infer trust from similarity, type, status, or a link label. Tags may be displayed, but tag filtering is not claimed by the inspected `KnowledgeSearchPolicy`.

Show applied values as removable controls with Clear all. Use OR within a category and AND between categories. Distinguish pending filter edits from the policy of the displayed results. Preserve applied filters on Back; distinguish zero results from missing index, unavailable runtime, and incomplete data. Full visibility semantics and acceptance are in the filter/diff companion.

Git status filters initially belong only to Changes. A descriptive Git badge is not changed-only retrieval. Any future changed-only search needs an exact pre-ranking path-set contract and both Git-observation and search-generation identities.

### Results and inspection

Each match shows rank, title/path, concept type, cited source line range, snippet, and the actual mode-specific score. Explain the score label; it is not a confidence percentage or a probability. Do not compare BM25, dense, and fused scores on a common scale.

Keep **Matches**, **Related context**, and **Notices** distinct. A context hit carries its returned reason and via-path where available; it is not another independently ranked match. The existing knowledge search returns one best passage per concept. Inspection may expose other passages without changing that search contract. Effective restrictions must not be silently undone by expansion; label and test any explicit separate context-policy exception.

Selected result details show its passage, chunk kind, metadata, heading context where available, and the exact indexed source revision. Open the corresponding source and check for revision divergence before highlighting a current-file range. If the file changed or disappeared, retain the historical hit with an explicit warning instead of showing an unrelated current passage as evidence.

### Optional comparison

The first searchable workbench must ship normal semantic search and inspection. A small advanced comparison action can subsequently run BM25, dense, and hybrid through the same library against the same snapshot, query, eligible concepts, limits, and context settings. Display separate result lists, overlap, timings, and mode labels; unavailable modes stay unavailable. Do not silently fall back from semantic to keyword search.

Record cold/warm resource state when interpreting timing. Any claim of improved relevance needs a fixed authorized fixture and relevance judgments, with the metric and regressions recorded. A result-list inspection alone establishes no winner. No cross-encoder service, new model, or benchmark dashboard is required for the first release.

## Index and embedding inspection

Show observed index state: not built, current, outdated, busy, missing model/runtime, incompatible, or failed. Preserve the backend's actual distinction: the current runtime groups some missing/stale/incompatible errors, so a more specific status needs W08 evidence rather than message-string guesses.

The read-only SDK inspection view should expose, when actually available, the bundle identity, completed generation, source fingerprint, configuration identity, active model descriptor, distinct indexed concepts, passage count, compatible-vector count, and token-fitting diagnostics. Persist no new claims of build time if the old format does not record it; label only observed times. Do not equate a model file existing with successful verification or successful native loading.

Inspect one concept or bounded page of passages at a time. Show source lines, chunk kind, whether a compatible vector exists, the model identity/dimension, and the effective embedding input/context only when retained or exactly recoverable through the owning library. Normalized/fitted retrieval input is not the complete original document and is not an editable block.

Surface `oversized_segment_split` and `embedding_context_omitted` where the snapshot reports them. Do not reconstruct a guessed embedding input, fabricate progress percentages, dump every vector, or add a 3D embedding plot. Vectors are not needed to diagnose most mapping, freshness, or type problems.

Refresh Search Index updates derived retrieval data. Label it differently from generating OKF navigation files; the two existing `index` verbs do different jobs. Keep the prior completed generation safe on failure. A force rebuild, cache removal, or model download requires a distinct explicit action, not an opening side effect.

Until W06/#110 changes coordination, respect busy and stale refusals. UI browsing and validation must remain usable. Never remove locks, open an index database independently from Flutter, or promise search-during-refresh. Suppressing an obsolete UI result is not cancellation of native work or a safe rollback.

## Changes and source comparisons

WB03 adds a scoped local Git reader and unified native source diff. The GitHub connector used to update this PR is not a runtime dependency. No login, remote, network, Git initialization, or automatic installation is needed for Changes.

Staged means pinned HEAD to Git staging index. Unstaged means staging index to saved working tree. Untracked means absent to saved new file. Keep both groups when a file has staged and unstaged changes. Later saved-buffer and indexed-current comparisons use their actual captured sources, never misleading HEAD labels.

Retain old/new paths and line numbers, final-newline markers, whitespace policy, and completeness. Unified view comes first; a later side-by-side layout reuses the same comparison model. Raw Markdown/YAML remains authoritative; previews and metadata summaries are supplementary. Filtered/partial views must not imply that hidden changes are clean or reviewed.

The reader uses tested argument arrays, NUL-delimited path records, selected-root containment, controlled process configuration, bounded output, and explicit unsupported states. External Git helpers/filters require a fail-closed policy; read-only is not a sandbox. No stage/commit/checkout/reset/apply/push/fetch/config mutation. Keep source bytes, Git staging index, refs, and configuration unchanged. See the companion for package research and full safety acceptance.

## Shared implementation

Keep the proposed app in `apps/wayfinder_workbench/` as an independent Flutter package with its own lockfile and Flutter checks. Do not alter the root Dart workspace's toolchain merely to host this consumer.

WB01 can use public `okf` and `wayfinder` libraries without model setup. W08 extends the extracted SDK for filtered search and bounded read-only inspection. WB02 uses those public operations. The full search-enabled app has native dependencies; the earlier model-free bootstrap is not a claim of native-free packaging.

Use AckInfer for new SDK-owned search/inspection request contracts, with explicit defaults and runtime validation even after direct construction. Do not change W01's existing CLI/MCP JSON Schema to smuggle in UI options. Add and test the new contract after W03 while preserving old calls. Reuse upstream metadata, finding, snapshot, and result types; do not generate a second OKF domain model.

No persistence internals or CLI `src` imports from the app. Resource ownership, model verification, freshness, filter-before-ranking, and generation locking stay in shared runtime code. No new SQLite/FTS engine, embeddings implementation, or generic Profile platform.

If W05/W06 have landed before W08, build on those public interfaces rather than create a competing lifecycle. The tickets have no artificial dependency on those improvements: the first implementation may use serialized operations and existing per-call lifetime.

The owned shell composes the pages with one root/request coordinator. Keep operation work off the UI rendering path and test responsiveness with the actual backend. Do not pass native handles freely between isolates or claim that an async signature guarantees responsiveness. The local Git reader stays inside the app until a second real consumer justifies extraction.

## Delivery and acceptance

| Item | Complete outcome | Blocked by |
| --- | --- | --- |
| [WB01](tickets/WB01-shell-and-validation.md) | Installed dashboard shell; open/read/validate a real folder; inspect findings. | None in the ticket graph; verified Flutter/Remix setup required. |
| [W08](tickets/W08-filtered-search-inspection.md) | Public typed filtered search and bounded index/passage inspection, used by a direct Dart consumer. | W03. |
| [WB02](tickets/WB02-search-and-inspection.md) | Refresh index, semantic search, visible concept filters, source/result inspection, and truthful failures. | WB01, W08; verified native assets required. |
| [WB03](tickets/WB03-git-changes-and-diffs.md) | Filter local Git changes and inspect correctly labeled source diffs without repository writes. | WB01; Git optional to the rest of the app. |

The first searchable workbench is WB01 plus WB02, not WB01 alone. WB03 is an independent review capability. W01–W03 remain the only active assigned implementation batch. New items are planned, not completed or dispatched. Safe source editing and Super Editor remain F01/F02. F03 is later editing/concurrent-search integration; reuse established search behavior rather than build a second surface. W07/#45 still owns Profile-aware structured writes.

Acceptance must demonstrate an invalid document that still opens; identical app/library validation findings; a real index/search/open-citation workflow; concept eligibility before limiting; custom types; separate concept/chunk types; ranking/context separation; exact source-tree non-mutation; missing native/model states; stale/busy failures; folder switches with late responses; and no automatic downloads.

Test a relevant concept outside an unfiltered top-five window that becomes reachable after a type filter. Test combined and cleared filters, pending-versus-applied policy, hidden validation errors, repeated chunks without inflated counts, deleted/changed sources, Unicode/line-ending citations, failed indexing, and two operations on one bundle. Compare default app/SDK/CLI results on the same fixture and configuration. Do not claim fresh-index parity for different snapshots.

WB03 additionally tests staged/unstaged/untracked separation, selected-subfolder isolation, renames/deletions, unusual filenames, incomplete diffs, line-ending markers, helper-policy refusal, missing Git, and source/staging-index/ref/config non-mutation. Synthetic command checks do not replace the actual adapter and UI tests.

Run actual generated-code stability, independent package resolution, Flutter analysis/tests, keyboard focus/text scaling, narrow-window behavior, light/dark appearance, and responsiveness checks on the stated desktop target. A minimal browse/validation path must survive missing retrieval assets or Git. Native skips and platform gaps are not passes.

## Diagnostic privacy and review

Debug is local and bounded. Default export includes operation metadata, relative paths, explicit capability states, and redacted findings. Queries, snippets, raw reports, model paths, document metadata, Git paths, and diff contents may contain private material; require preview/explicit inclusion for expanded exports. Do not log bodies, vectors, credentials, full diffs, or payloads by default. No telemetry or automatic upload.

Reading or previewing must not execute Markdown code/HTML, fetch remote resources, or launch arbitrary schemes. Apply the same containment and symlink policy to folder traversal, assets, index inspection, citation navigation, and Git review. Unknown data is source material, not instructions.

Review Standards and Spec separately against fixed base/head. Standards covers ownership, template use, theme/overlay setup, no duplicated search/storage, generation, native/process lifetime, and privacy. Spec covers every listed workflow and truthful state. This update is author source review and planning, not independent implementation review. No Flutter app, Dart generator, native embedding test, or relevance benchmark ran here. The separate synthetic Git experiment and its limits are recorded in the filter/diff companion and status document.

## Sources

- R1: Promoted registry, including dashboard_shell and dashboard_demo: https://github.com/btwld/remix/blob/849dbc0c03348f13f8a99bb50bebd3b0e1321012/registry/vanilla/registry.yaml
- R2: Shell template and host-owned slots: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/registry/vanilla/templates/dashboard_shell/dashboard_shell.dart.tmpl
- R3: Previously verified runtime beta: https://pub.dev/packages/remix/versions/1.0.0-beta.10
- R4: Source-pinned CLI and installed-source workflow: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/packages/remix_cli/README.md
- R5: Theme, host, and pin rules: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/skills/using-remix/SKILL.md
- W1: Runtime defaults, freshness, and resource lifetime: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/packages/wayfinder_cli/lib/src/knowledge.dart
- W2: Library search modes, policy, and result model: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/packages/wayfinder_embeddings/lib/src/okf/knowledge_index.dart
- W3: Existing wire result: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/packages/wayfinder_cli/lib/src/search_output.dart
- W4: Model descriptor: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart
- W5: Snapshot, context input, and token-fitting diagnostics: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/packages/wayfinder_embeddings/lib/src/okf/knowledge_snapshot.dart

Related: [Adjustment](ADJUSTMENT.md), [filters/diff research](FILTERS_AND_DIFFS.md), [active Batch A](../wayfinder-sdk-batch-a.md), [manifest](task-manifest.json), [status](STATUS.md).
