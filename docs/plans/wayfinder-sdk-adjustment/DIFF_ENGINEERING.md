# Diff engineering and dependency review

Revision 6 · 28 September 2026 · draft decision and implementation gates.

Reviewed planning base: `c610f0c112bea5e052d950c2410a55001b018d98` in PR #112.

This document supersedes the package preference order in revision 5 of [FILTERS_AND_DIFFS.md](FILTERS_AND_DIFFS.md). That document remains authoritative for visible filters, comparison sides, root containment, privacy, and read-only Git policy. This revision does not weaken those rules, add a new active batch, or claim that a viewer has been implemented.

## Decision

Do not make the application depend on an old text-diff widget as its Git review implementation.

Use installed Git for repository comparisons, an application-owned immutable comparison model for correctness, and a native Flutter text surface for display. First test Re-Editor in read-only mode because the app already proposes it for source editing. Re-Editor is a renderer candidate, not a Git parser or a proven drop-in diff viewer.

For the first Git workflow, no Dart diff algorithm is required: Git already supplies the patch. For later comparisons between two in-memory sources, evaluate `diffutil_dart` over exact line tokens. Keep `diff_match_patch` and `pretty_diff_text` out of the default dependency set. Do not replace a small missing viewer with a new full editor, a fork of multiple packages, or an invented diff algorithm.

If the native text-surface test fails, record the missing capability. A locally bundled `diff2html` view is the first web-renderer alternative to evaluate; Monaco's diff editor is another option when full source models and editor capabilities are actually needed. Neither is an approved Flutter desktop dependency in this plan. Do not quietly introduce a WebView or Node runtime.

## What the maintenance review establishes

These are package/source observations on the review date, not a resolved lockfile or support guarantee. Cached pub.dev pages report inconsistent relative ages, so no exact release day is inferred from them. Release age alone does not establish that a stable algorithm is broken or abandoned.

| Candidate | Evidence and fit | Decision |
| --- | --- | --- |
| `diff_match_patch` 0.4.1 | The version list shows an old published release. Separately, Google's original multi-language repository was archived on 5 August 2024. The Dart port and the archived upstream are not the same maintenance entity. Plain-text operations do not supply Git states, hunk navigation, or a Flutter review surface. [S1, S2] | Not the default for new work. A future use needs its own compatibility evidence and maintenance rationale. |
| `pretty_diff_text` 2.1.0 | RichText-based display, MIT, with a `withDiffs` constructor, but still a declared dependency on `diff_match_patch`. It is useful for short inline comparisons; its documented surface does not establish Git hunk parsing, virtualized selection, or paired line numbers. [S3] | Do not use as the main viewer. `withDiffs` is not a way to remove its transitive dependency. |
| `diffutil_dart` 5.0.0 | Apache-2.0, Dart 3, list edit operations using Myers. Its current changelog adds performance work, a benchmark harness, and regression cases. It also explicitly changes which valid anchors can be selected in duplicate-heavy inputs. [S4] | Preferred algorithm candidate for a later source-pair comparison, not for re-diffing Git's patch. Test repeated lines and source reconstruction; do not assume its edit positions are Git line numbers. |
| `re_editor` 0.10.0 | MIT. The publisher documents read-only mode, large-text support, scrolling, custom indicators, find, and selection/shortcut behavior. Its public barrel exports the editor library, not a diff-viewer interface. [S5] | First native text-surface experiment. Require public customization points and real desktop tests; do not fork it or depend on private `src` imports merely to add gutters. |
| `git` 2.3.2 | BSD-2-Clause command wrapper, not a Git implementation or a security layer. [S6] | Optional, not required. Prefer the existing small process adapter when it provides clearer raw-byte, timeout, environment, and cancellation control. |
| `diff2html` / Monaco | Their primary repositories document browser-based diff rendering/editor capabilities. They are not Flutter widgets. `diff2html` accepts unified patches; Monaco works with original/modified models. [S7, S8] | Conditional alternatives only. Their integration cost must include host support, source escaping, focus, copy, offline assets, licensing, and release packaging. |

The official `webview_flutter` package currently lists Android, iOS, and macOS, not a complete Windows/Linux desktop solution. Other hosts may support those platforms, but must be evaluated rather than assumed. A maintained JavaScript renderer does not automatically yield a maintained cross-desktop Flutter integration. [S9]

No maintained drop-in native Flutter Git review widget satisfying this app's full contract was verified by this review. This is a limit of the review, not a claim that no such widget exists.

## Keep three responsibilities separate

### 1. Read the comparison

The local Git module owns discovery, authorized-root scoping, safe process invocation, source capture, and repository-state interpretation. It returns either an identified change inventory or one identified comparison, with bounded output and explicit failures. Keep it in the app until another real consumer justifies extraction.

Retain the comparison sides from the filter/diff plan: HEAD to staging index, staging index to saved working tree, and absent to untracked file. Capture hashes/object IDs and byte interpretation. Recheck for changes during loading. Do not present Git-normalized text as a byte-identical copy of the working file.

Git is also a useful independent oracle for fixtures, but only when the test pins the input pair, options, and Git version. A different valid algorithm may choose different anchors for repeated lines. Git documentation also distinguishes raw records, ordinary patches, and combined merge diffs; they are not interchangeable input grammars. [S10]

### 2. Describe the comparison

Use one immutable application value with the following concepts. Names are proposed, not existing exported APIs.

| Value | Information it must retain |
| --- | --- |
| Comparison identity | Selected root, comparison kind, old/new identity or hash, generating engine/options, and read observation. |
| Source side | Origin, authorized path if applicable, present/absent/unavailable state, captured bytes or safe handle, encoding, and original line terminators. |
| File change | Both paths, change kind, relevant mode metadata, and complete/partial/unsupported state. |
| Hunk | Old and new start/count values plus rows; metadata is not counted as a source line. |
| Display mapping | Display row to old/new logical line or none; alignment placeholders and hunk headers are not source text. |
| Diagnostics | Missing source, changed while reading, truncated output, invalid patch, unsupported binary/conflict format, or policy refusal. |

Read raw/NUL-delimited metadata for file identity rather than deriving names from display headers. Parse only the controlled ordinary unified-patch subset produced by the reader initially. Accept omitted hunk counts as one and explicit zero-length ranges as zero. Count context on both sides, removals on the old side, and additions on the new side. A missing-final-newline marker belongs to the preceding side/row and does not increment either counter.

Validate declared hunk counts and ranges. A line containing `---`, `+++`, or `@@` inside a hunk is interpreted through the current parser state, not a global header regex. Unknown or combined patch forms remain inspectable as bounded raw data with an unsupported notice. Truncation or parser failure must never produce an empty successful diff.

Keep original source bytes separate from normalized display text. Do not parse or regenerate YAML to compute the source diff. Frontmatter summaries can explain a change, but they do not replace it.

### 3. Display and review it

The renderer receives an already computed comparison. It does not run Git, own filesystem paths, rewrite source, or decide which files are in scope. Remix supplies shell controls and theme values; the comparison module supplies line identity and state.

Start with one selected file, unified view, explicit Refresh, Previous/Next Change, visible old/new labels, and a bounded raw-patch fallback. Do not start with a custom rendering engine, infinite multi-file canvas, conflict resolver, or full history browser.

## Native renderer acceptance experiment

Use a read-only Re-Editor text surface with the public controller/indicator/scroll interfaces, keeping rendered-row mapping outside that controller. Hunk headers and markers can be display text; old/new gutters must use the comparison mapping instead of the editor's display-line count. Do not claim that normal source line numbers solve diff gutters.

The experiment must prove all of these before adopting it for WB03:

- Selection and copy across multiple added/removed/context lines, through scrolling and virtualization.
- Correct old/new gutters, hunk navigation, long lines, tabs, and text scaling using public extension points.
- Read-only behavior under typing, paste, shortcuts, context menus, and input methods.
- Remix light/dark token mapping, keyboard focus, and a clear accessible name for each side and change.
- No reconstruction of original source from the editor controller, which may normalize text for display.

Disable automatic code folding and code-completion behavior that do not understand diff rows. Use an explicit hunk-collapse operation only after its selection and mapping behavior is tested. Do not attach one TextField per row or infer that a ListView of SelectableText widgets provides correct continuous offscreen selection.

Define copy actions explicitly: Copy displayed patch copies patch text; Copy old/new hunk extracts the actual captured side lines, excluding gutters, markers, and alignment placeholders. Native clipboard newline conventions must be tested. Exact-byte export, when offered, reads captured bytes, not UI text. Do not label lossy display copy as byte-preserving export.

If a required capability would need private editor internals, either ship a clearly bounded native patch viewer with the reduced supported behavior or evaluate the web alternative. Document the decision and missing acceptance; do not mark a degraded prototype as full WB03 completion.

## In-memory comparisons and intraline decoration

Do not add an algorithm solely because its name includes diff. The first tracked Git comparison uses Git-produced hunks. Untracked additions can be described directly as absent-to-source.

When saved-buffer or indexed-current comparison becomes real through F01/WB02, evaluate `diffutil_dart` with move detection explicitly disabled and equality over exact line tokens, including terminators. Preserve an absent file separately from a present empty file. Convert ordered edit operations into a coherent alignment; mutable list-update positions must not be displayed directly as original/new source coordinates.

Tests must reconstruct both source streams and preserve mapping after duplicate lines, empty files, CRLF/LF changes, and final-newline changes. The 5.0.0 anchor change makes golden row snapshots version-sensitive; test semantic correctness as well as approved visual output. Store the algorithm/version/options in reproducible fixtures.

Only then add optional intraline highlighting inside a bounded replacement block. Treat grapheme boundaries, surrogate pairs, combining characters, and bidirectional controls deliberately. A budget timeout skips decoration with whole-line highlighting still available. It must not change Git's authoritative hunk boundaries or pretend that a partial algorithm result is an exact comparison. Never use fuzzy patch application for saving or applying reviewed changes.

## Performance, failure, and review state

Select documented byte, line-count, longest-line, computation, and output caps in the experiment. Record them with measurements on a named desktop; this plan does not invent a throughput guarantee. At a cap, display the reason and retained coverage, not a success/clean state. Large-file refusal is preferable to freezing the UI.

Do work outside the UI frame path. A Future alone is not off-thread execution, and a timeout wrapper does not stop a synchronous algorithm. Use a bounded worker/isolate or process with real termination rules. Reject late results by comparison identity and request generation. Limit cache size and retain no unrequested document bodies in diagnostics.

Use addition/removal roles and plus/minus indicators, not colors alone. Start with wrap disabled for deterministic source-row layout; add wrapping after mappings and navigation survive it. A split view must use aligned row geometry or explicit logical-line anchors. Two independent scroll percentages are not reliable synchronization when rows wrap or one side has gaps.

Viewed state remains keyed to the entire identified comparison and completeness. Hiding unchanged lines, filtering files, collapsing hunks, or scrolling to the bottom does not prove review. A changed hash resets any marker. Keep filtered inventory totals and full validation verdicts visible as previously specified.

## Web alternative: a decision gate, not a hidden dependency

Prefer a packaged local `diff2html` experiment for read-only Git-patch presentation before adopting an entire browser editor. Evaluate Monaco when working with full source pairs or richer editing actually repays its integration cost. Retain raw Git output and label any recomputed alignment instead of claiming it is Git's exact grouping.

A web experiment must load versioned local assets with no CDN or remote page, use an appropriately restrictive policy, escape untrusted source as data, block external navigation/network requests, and expose only a narrow versioned message interface. JavaScript cannot read arbitrary local files or execute Git. Avoid embedding source in URLs or general-purpose evaluation strings.

Prove host support and packaging on each advertised desktop, keyboard/copy behavior, text scaling, source-hash correspondence, disposal, memory limits, and zero unintended network traffic. Do not add Node as an application runtime merely to render a patch. No provider or renderer switch happens automatically because a test is difficult.

## Delivery within the existing ticket graph

Keep 16 work items. Strengthen WB03 rather than creating an unbounded new package/project.

1. **Selected-file read-through:** load a controlled staged/unstaged/untracked comparison, show exact side labels and a bounded native patch, and prove read-only behavior. Complete parser/model fixtures accompany this slice.
2. **Renderer acceptance:** prove selection/copy, mapped gutters, navigation, theme, limits, and stale-result behavior in the actual Flutter app. Accept or reject the Re-Editor integration with evidence, not a demo screenshot alone.
3. **WB03 release gate:** run the full existing root/process/unsupported-state acceptance and add the dependency report. This is when WB03 can be marked complete. Split view, intraline decoration, history, buffer providers, and semantic-index providers remain separately gated capabilities, not hidden prerequisites.

All three remain inside the scope of a later assigned WB03 implementation. W01–W03 stay the only currently active assigned batch. No merge, publication, source writes, staging/committing, remote Git operation, or agent dispatch is authorized by this planning update.

## Required evidence

Record the resolved Flutter/Dart/package versions, package source revision, declared licenses/notices, tests actually run, known issues that affect this use, and a fallback/removal path. Pub scores, download counts, recent commits, and platform badges are signals, not evidence that this app works. Do not add unreviewed overrides to force dependency resolution.

Use synthetic/authorized fixtures for all source/patch tests. Include add/delete/rename, one file both staged and unstaged, header-like content, zero/omitted hunk counts, no-final-newline markers on either side, repeated lines, empty/absent files, long lines, invalid/truncated patch, unsupported combined/binary changes, changed sources, no Git, and blocked helper configurations. Assert full source/index/ref/config non-mutation and selected-root containment independently of what the renderer displays.

Run static checks, ordinary and randomized reconstruction tests, selected desktop integration, and the selection/copy/performance experiment. Rendering and helpers require platform-specific evidence; a Python or command-line probe cannot certify them. Review Standards and Spec separately at fixed base/head and label self-review honestly.

## This review's limits

This session read the existing WB03 and planning state through GitHub, primary publisher pages/changelogs, Git documentation, and relevant editor exports. `dart` and `flutter` were not found in the authoring environment. No candidate was installed, generated, compiled, or run. Direct container downloads also failed DNS resolution; source inspection used the connected GitHub and web tools. No fresh Git experiment or full plan-checker result is asserted here. The historical 11-check report from revision 5 is not new evidence for this revision. No independent reviewer or implementation agent ran.

## Sources

- S1: https://pub.dev/packages/diff_match_patch/versions
- S2: https://github.com/google/diff-match-patch
- S3: https://pub.dev/packages/pretty_diff_text and https://pub.dev/packages/pretty_diff_text/changelog
- S4: https://pub.dev/packages/diffutil_dart/changelog and https://github.com/knaeckeKami/diffutil.dart/blob/master/CHANGELOG.md
- S5: https://pub.dev/packages/re_editor and https://github.com/reqable/re-editor/blob/main/lib/re_editor.dart
- S6: https://pub.dev/packages/git and https://api.dart.dev/dart-io/Process/start.html
- S7: https://github.com/rtfpessoa/diff2html
- S8: https://github.com/microsoft/monaco-editor
- S9: https://pub.dev/packages/webview_flutter
- S10: https://git-scm.com/docs/diff-format and https://git-scm.com/docs/git-diff

These references establish observed package capabilities and format rules. The application module design, acceptance gates, and choices are proposed engineering decisions, not claims of implemented support.
