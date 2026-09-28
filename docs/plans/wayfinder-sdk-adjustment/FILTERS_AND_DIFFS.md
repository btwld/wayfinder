# Filters, change visibility, and Git diff review

Planning revision 5 · 27 September 2026 (America/New_York). Draft requirements, not implemented behavior.

Review base: `6bb3096f711a32f0486c7002301188ebf71023ac` in PR #112. This extends [WORKBENCH.md](WORKBENCH.md). It makes filter visibility explicit and adds a read-only Changes destination when Git is available. W01–W03 remain the active assigned batch. No repository-writing Git feature is authorized.

## Decisions

Use the existing Remix Vanilla dashboard shell and controls. Keep Wayfinder semantic retrieval as the default. Put a small, optional local Git reader behind the Changes page; do not turn the app into a Git client or add Git as a requirement for browsing, validation, or search.

The GitHub connector used to review and update this PR is not the app's runtime. The desktop app reads the user's local repository through the installed Git executable. It does not need a GitHub account, remote, token, or network connection.

Use a native Flutter unified diff as the first presentation. Add side-by-side layout over the same comparison model after its correctness and keyboard behavior pass. Raw Markdown/YAML source is the diff authority. Rendered previews and parsed metadata summaries are optional companions, never substitutes for source changes.

## Visible filters

Each destination owns a controlled filter selection. Share small presentation pieces, not a global filter whose meaning changes invisibly between pages. Show active values as removable chips, an accessible Filters control, and Clear all. A filter is never represented only by a hidden popover. Returning from a detail view retains query, filters, selection, scroll position, and the associated result revision.

| Destination | Initial filters | Meaning |
| --- | --- | --- |
| Library | Filename/path text; optional document-kind grouping | Model-free filtering of loaded file inventory. Broken YAML and plain Markdown remain discoverable. |
| Search | Concept type and path prefix; supported lifecycle controls only in Advanced | Eligibility in Wayfinder before ranking and limiting. No filtering just the returned top five. |
| Passage inspection | Selected concept and supported chunk-kind filter | A bounded view over one identified snapshot, not the normal one-best-passage-per-concept search contract. |
| Validation | Severity, rule code, path, OKF/Profile layer | Presentation filtering of the complete returned report. The full validation verdict never changes. |
| Changes | Path text; staged/unstaged/untracked/conflict group; added/modified/deleted/renamed kind | Presentation of an identified, complete Git change inventory within the selected root. |

Within one multi-value category, use OR. Between independent categories, use AND. Empty selections mean all eligible values. Keep project-defined concept types as strings with their original spelling. Distinguish concept type, chunk kind, content format, lifecycle state, Git status, and index freshness.

Keep editing filter controls separate from submitted results. A changed filter marks the displayed results as belonging to the previous request until Apply/Search completes. Do not put new chips above old results as though the request had already run. Clear all resets the controls and either submits explicitly or visibly marks results pending.

Counts must identify their population and revision. Library/Changes may say '8 of 21 files shown' only after a complete inventory; partial scans say '8 loaded; scan incomplete'. Search shows returned matches, limit, and known eligible concept count separately. It must not call top-k results the total matching corpus. Facets count distinct concepts, not passages. Missing counts are unavailable, not zero. Validation says '3 of 12 findings shown' while retaining the full error/advisory totals and verdict.

Unparseable or absent metadata is visible as an application diagnostic category; do not write an invented `unknown` concept type into source. Tags can be displayed, but a tag filter is not enabled until its supported retrieval semantics and tests exist. Apply the same honesty to chunk-kind filtering: inspect a bounded snapshot through a public operation, never filter one returned page and claim complete counts.

Related context remains separate from matches. Show its inclusion reason and any restriction that excluded context. Do not silently bring back out-of-scope documents through relationship expansion. Any explicit context-policy exception must be labeled and tested.

Initially, Git-state filters belong to Changes only. A future 'search changed documents' option must join exact path sets into pre-ranking eligibility and identify both the search generation and Git observation. A Git badge on an existing hit is descriptive, not proof that changed-only retrieval was applied.

Remix provides Select, CheckboxGroup, Popover, badges, and buttons, but the app owns filtering behavior. Use installed recipe APIs and preserve keyboard/focus semantics; a badge does not become a removable chip without a real labeled control. Do not install another UI framework for this. [R1]

## Five destinations, one explicit folder

Library, Search, Validation, and Index remain as specified. Add **Changes** to the same shell. Its layout is a filtered file list, a comparison selector, a diff pane, and a compact summary of selected root, Git state, and revisions. No new metrics dashboard or nested application shell.

Git unavailable, non-repository folder, unsupported repository, permission failure, policy-blocked access, no changes, and loading are distinct states. Do not run `git init`, clone, fetch, or install Git on folder open. The other destinations remain usable without Git.

Git's staging index and Wayfinder's search index are different structures. Use the full terms in diagnostics and actions. Refresh Changes is a read. Refresh Search Index writes only derived Wayfinder data. Neither action stages files or regenerates OKF navigation.

## Name both sides of every comparison

| Comparison | Old side | New side |
| --- | --- | --- |
| Unstaged | Git staging index | Saved working-tree file |
| Staged | Pinned HEAD commit | Git staging index |
| Untracked | Empty/absent file | Saved untracked file |
| Unsaved editor changes, later with F01 | Saved editing baseline | Current unsaved buffer |
| Indexed source versus current, when WB02 supplies it | Source retained by the identified Wayfinder generation | Current saved source |
| Committed comparison, optional later | Explicit pinned commit A or an explicitly selected merge base | Explicit pinned commit B |

Ordinary `git diff` and `git diff --cached` compare different pairs. A file can occur in both groups with different changes. Untracked files are not automatically included in a tracked-file diff. [G1, G2]

Never use `HEAD` as a label for a Wayfinder source snapshot. Do not mix buffer edits into a working-tree diff. Resolving a branch name to an object ID is required before an optional commit comparison; an A-to-B diff and merge-base-to-B diff must have different labels.

Pin commit/blob IDs where available and hash the captured staging/working/buffer bytes. A Git command sequence is not a transaction. Recheck the relevant state around loading and show 'changed while reading; refresh' when it diverges. Keep the user's current diff stable until explicit refresh rather than jumping the view mid-review. Reject late responses from another root, filter request, path, or comparison.

Deleted files open their old side without requiring a current file. Renames retain both paths and the actual observed/detected status. When a rename crosses the selected folder boundary, do not read outside the authorized root merely to reconstruct its other side; show an unavailable/out-of-scope side. Detached HEAD, an unborn branch, worktrees, merge conflicts, symlinks, mode-only changes, submodules, binary files, and LFS pointers need explicit cases, not silent empty diffs. Full history browsing and conflict resolution are not required.

## Correct diff rendering

The first renderer consumes files and hunks with old/new line numbers, line kind, raw line text, terminator information, source identity, and a complete/partial flag. Do not recover filenames by splitting human-readable patch headers on whitespace.

Show additions, removals, context, hunk headers, file renames/modes, and missing-final-newline markers. Use plus/minus symbols and accessible labels as well as colors. Preserve selectable text and correct copy behavior. Intraline highlighting is optional decoration; it must not alter source, Git hunks, or line mappings.

Unified view is the default, including narrow windows. Side-by-side uses the same immutable comparison, blank alignment rows, and stable old/new gutters. Wrap changes layout, not logical line numbers. Expanding context needs captured source and cannot invent omitted lines. Page or virtualize large comparisons; show size limits and truncation explicitly. Partial output cannot appear as a clean or fully reviewed file.

Whitespace-ignore is off by default and visibly labeled when enabled. YAML indentation, Markdown hard-break spaces, CRLF/LF changes, and final newlines matter. Keep an exact raw view available. A parsed frontmatter summary must say when formatting, comments, or unknown fields are omitted; do not round-trip files to create that summary.

An optional local 'Viewed' marker is keyed by root, path pair, comparison kind, side hashes, and completeness. It resets when content changes. Hiding files or hunks through filters never marks them reviewed. 'Viewed' means user navigation state, not validation, approval, or a Git action.

## Git reader and process safety

Start with the installed Git CLI through a small Dart `Process.start` adapter. Keep it inside the app until another real consumer needs the same module. The interface returns a scoped change snapshot or a bounded comparison and typed failures; it does not expose arbitrary command execution. [G4]

Use explicit executable resolution, argument arrays, a working directory, bounded stdout/stderr, timeouts, and cancellation/cleanup. Do not build shell strings. On Windows select a real Git executable rather than a `.bat`/`.cmd` wrapper, because those may invoke a shell despite `runInShell: false`. Drain both output streams. [G4]

Use Git discovery rather than assuming `.git` is a directory; worktrees can point elsewhere. Scope inventory and diff requests to literal paths under the selected root. A Git root above the selected folder does not authorize displaying sibling files. Keep raw path bytes where possible; visibly escape control characters, and report unsupported path decoding rather than corrupt identities.

Use machine-readable NUL-delimited status/name records, such as porcelain v2 with `-z`. Parse ordinary, rename/copy, unmerged, and untracked records separately. Do not split on newlines or spaces, and do not infer rename history from the current filename alone. [G1]

The reviewed command categories are repository discovery, scoped status, reading object metadata/bytes, and bounded diffs. For trusted supported repositories, disable pagers/colors, external diff and text conversion, optional staging-index refresh, fsmonitor hooks, credential prompts, and lazy object fetching using tested options/environment. Treat the command's exit conventions explicitly; `git diff --no-index` returns 1 for differences, not just failures. [G1–G3, G5]

**Read-only is not a sandbox.** `--no-ext-diff` and `--no-textconv` do not disable every Git extension. Clean/process filters and repository configuration can run helpers or change byte interpretation. Before working-tree status/diff operations, inspect the relevant configuration/attributes through a tested non-executing path. Block unsupported external-filter repositories by default unless an explicit reviewed policy can safely handle them. Do not edit repository configuration, bypass ownership checks with a wildcard safe.directory, or claim hostile-repository safety without adversarial tests. Preserve whether comparisons use Git-normalized bytes or raw file bytes; never silently substitute one. [G2, G3]

Submodules and symlinks are metadata-only initially; do not recurse or follow them out of the selected root. Missing objects in partial clones remain unavailable instead of causing network fetches. Use a controlled environment that strips inherited Git redirection/helper variables. Fail closed when the installed Git version cannot enforce the required controls. Git installation/bundling and dependency licensing need a separate distribution check; no Git executable is bundled by this plan.

No stage, unstage, commit, checkout, reset, restore, clean, stash, merge, apply, push, fetch, config mutation, or automatic helper/model download. Refresh and viewing must leave tracked/untracked bytes, the Git staging index, refs, and repository configuration unchanged. User review marks live in application state outside the bundle.

## Package research and proposed selection

The package pages below were inspected; none was installed or compiled in this session. Versions are dated observations, not guarantees for a future lockfile.

| Candidate | Verified role/license | Decision for the first workbench |
| --- | --- | --- |
| `dart:io` Process + installed Git | Official process interface and native Git semantics | Preferred small read-only adapter, with the controls above. |
| `git` 2.3.2 | Dart Git command wrapper, BSD-2-Clause | Viable convenience option, not a Git implementation or safety layer. Use only if raw bytes, environment, lifecycle, and limits remain controllable. [P1] |
| `diff_match_patch` 0.4.1 | Plain-text diff/match/patch algorithms, Apache-2.0 | First candidate for bounded intraline or in-memory source comparisons. Never use fuzzy patch application for saves or staged changes. [P2] |
| `diffutil_dart` 5.0.0 | Generic list edit operations, Apache-2.0 | Alternative for line-token alignment/list updates, not a Git parser or complete viewer. Do not install both algorithms without demonstrated need. [P3] |
| `pretty_diff_text` 2.1.0 | RichText-based text difference display, MIT | Optional short-preview prototype. Its documentation does not establish file/hunk parsing, line gutters, virtualization, or staged/unstaged semantics. Not the main viewer by default. [P4] |
| `diff` 0.1.1 | Package page labels it Dart 1 only | Exclude from the modern Flutter shortlist. [P5] |

Searches did not establish a maintained drop-in native Flutter Git review widget satisfying all of these requirements. That is not a claim that none exists. Build the thin native renderer on a tested comparison model and existing Remix tokens; evaluate a discovered candidate against the same fixtures before replacing it. No WebView/Monaco, second UI framework, or new reusable diff package is needed initially.

## Delivery and tests

Strengthen W08 with effective filter policy, labeled facet counts, public bounded passage filtering, and separation of query matches from context. Strengthen WB02 with visible applied filters, Clear all, stale-request handling, and honest empty/partial states. Do not change W01's established CLI/MCP request schema for these additions.

Add WB03, blocked only by WB01: an independent read-only local Git Changes workflow. It does not require semantic search, Super Editor, or concurrency changes. Once WB02 exists, reuse the same comparison view for indexed-source/current comparisons; once F01 exists, reuse it for saved/buffer comparisons. Neither is a prerequisite for initial Git review.

Required demonstrations: filter before top-k; OR/AND/default semantics; visible submitted filters and pending edits; full versus displayed findings; complete versus loaded counts; path-only/missing metadata; root isolation; staged and unstaged changes in the same file; untracked/add/delete/rename; final-newline and CRLF cases; Unicode/control characters; stale snapshots; no-Git operation; large/binary/mode/conflict states; blocked external helpers; source/index/ref/config non-mutation; keyboard/select/copy and light/dark/narrow layouts. A zero-result filter is not 'index empty' or 'all valid'.

A local synthetic experiment ran with Git 2.47.3: 11 checks passed, 0 failed. It checked NUL path records (including tab/newline/Unicode), subfolder isolation, staged/unstaged separation, rename records, deletion, final-newline markers, unchanged source and staging-index bytes after reads, and no-index exit 1. This was not the application or its adapter. Hostile filters, worktrees, conflicts, Windows/macOS, Flutter rendering, Dart resolution, and the full planning checker were not tested by that experiment. These remain acceptance work, not inferred passes.

Review Standards and Spec separately against fixed base/head. A self-review is not an independent agent review. This planning update adds no runtime implementation, launches no agent, and leaves PR #112 draft.

## Sources

- R1: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/skills/using-remix/references/components.md
- G1: https://git-scm.com/docs/git-status
- G2: https://git-scm.com/docs/git-diff
- G3: https://git-scm.com/docs/gitattributes
- G4: https://api.dart.dev/dart-io/Process/start.html
- G5: https://git-scm.com/docs/git
- P1: https://pub.dev/packages/git
- P2: https://pub.dev/packages/diff_match_patch
- P3: https://pub.dev/packages/diffutil_dart
- P4: https://pub.dev/packages/pretty_diff_text
- P5: https://pub.dev/packages/diff

The package descriptions and Git documentation establish capabilities and semantics. UI behavior, policy choices, controls, and task sequencing above are proposed requirements, not claims of implemented features.
