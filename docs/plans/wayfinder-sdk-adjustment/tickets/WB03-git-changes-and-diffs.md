# WB03 — Inspect local Git changes with explicit comparison sides

**Batch:** workbench
**Status:** planned
**Blocked by:** WB01

## What to build

A person opens a local folder in the workbench, filters its changed files, selects staged or unstaged changes, and reads a correctly labeled source diff without modifying the repository. Git is optional; Library and Validation remain useful without it.

## Scope

Add Changes to the existing Remix dashboard shell. Keep three responsibilities separate: read an authorized Git comparison, validate an immutable hunk/source model, and render it. The renderer does not run Git or decide repository scope. Keep one comparison model for later reuse without implementing speculative source providers.

Use installed Git and a small read-only process adapter. Git supplies repository patches; a Dart text-diff algorithm is not required to recompute them. Evaluate Re-Editor in read-only mode as the first native text surface, using only public customization points. The app owns old/new gutters, display-row mapping, completeness, and revision labels. Do not treat an editor widget as a complete Git viewer.

The package selection and renderer gates in [DIFF_ENGINEERING.md](../DIFF_ENGINEERING.md) supersede the older preference order in the filter/diff research table. Do not introduce diff_match_patch or pretty_diff_text as default dependencies. diffutil_dart is a later source-pair algorithm candidate, not required for this first Git workflow. Browser renderers are alternatives requiring an explicit host/offline/security evaluation, not an automatic fallback.

Discover the repository/worktree correctly, restrict visible paths to the selected root, parse machine-readable NUL-delimited metadata, and retain both paths of a rename. Name old/new sources and capture revisions or hashes. Keep staged, unstaged, and untracked groups separate. Retain the configuration/attribute policy in FILTERS_AND_DIFFS: read-only commands are not automatically safe against repository-configured helpers.

Implement verifiable slices: first selected-file read-through with exact source labels and bounded patch; then the native selection/gutter/navigation experiment; then the full safety/compatibility gate. Partial slices must not be labeled completed WB03.

## Acceptance criteria

- [ ] Open → Changes → filter → select file → read unified diff works against a real synthetic Git repository using public app behavior.
- [ ] Active filters are visible, removable, and resettable; shown versus total counts are truthful; returning from a diff preserves filter and selection state.
- [ ] Unstaged compares staging index to working tree; staged compares pinned HEAD to staging index; untracked compares absent to saved source. A file can appear in both staged and unstaged groups.
- [ ] Ordinary unified hunks validate old/new ranges and counts, including omitted and zero counts, header-like source text, and missing-final-newline markers. Truncated/unknown formats cannot become empty successful diffs.
- [ ] Original bytes, line endings, logical old/new lines, and displayed rows remain distinct. A metadata summary or Markdown preview never replaces raw-source evidence.
- [ ] The renderer experiment proves cross-line/offscreen selection, mapped gutters, hunk navigation, tabs/long lines, read-only shortcuts, text scaling, and Remix light/dark styling using public interfaces. Private imports or required forks block adoption.
- [ ] Copy displayed patch and Copy old/new hunk have explicit, tested semantics. Gutters/placeholders are excluded from source copy, and display normalization is not claimed as exact-byte export.
- [ ] Root discovery supports a selected subfolder and worktree; out-of-scope rename sides, symlinks, and submodule contents are not read to fill missing context.
- [ ] Added/deleted/renamed files, unusual path bytes, unborn/detached HEAD, conflicts, binary/mode-only changes, and missing objects produce correct results or explicit unsupported states, never false clean results.
- [ ] Git missing, non-repository folder, policy-blocked repository, no changes, stale observation, and operation failure remain distinct. Other destinations remain usable.
- [ ] Commands use approved argument arrays, bounded streams/timeouts, tested helper/configuration controls, no network access, and no shell interpolation. Unsupported external-filter repositories fail closed.
- [ ] Refresh/view/filter/copy leave source bytes, the Git staging index, refs, and configuration unchanged. No staging, committing, resetting, applying, or downloading is exposed.
- [ ] Input/line/longest-line/output caps are measured and recorded. Crossing a cap produces an explicit partial/unsupported result; computation cannot block the UI indefinitely or survive a cancellation claim unnoticed.
- [ ] A local Viewed marker, if included, is comparison-specific and resets on changed content. Hidden or partial changes cannot be marked fully reviewed by navigation or filtering.
- [ ] Resolved dependency versions, source/notice inventory, actual platform tests, remaining gaps, and an accept/reject decision for the native renderer are recorded. Browser alternatives are not advertised as supported without equivalent evidence.

## Out of scope and external gates

Not part of active W01–W03. No GitHub account/remote integration, history browser, stage/commit controls, conflict resolution, Git installation, new storage engine, public diff package, or second design system. Super Editor, native embeddings, W06, and WB02 are not prerequisites.

Saved-buffer and indexed-source comparisons wait for real F01/WB02 providers. Split view and intraline highlighting follow the verified unified workflow; do not make a new alignment algorithm a hidden requirement for the first slice. Any reduced prototype retains explicit gaps rather than silently relaxing the final acceptance criteria.

## Test and demonstration evidence

Use synthetic repositories and exact old/new fixtures. Include simultaneous staged/unstaged changes, deletion, rename, untracked Unicode/control-character paths, changed files outside the root, absent/empty files, repeated lines, CRLF/final-newline cases, zero/omitted counts, header-like content, truncated/combined patches, and external-helper traps.

Hash repository/source state around reads and retain command options, exits, and capture identities. Verify source reconstruction and row mapping separately from visual snapshots. Run actual Flutter keyboard/select/copy and performance checks on the named desktop; a CLI or Python test cannot certify widget behavior. The historical 11-check report is preliminary evidence, not completion of this ticket.

## Review and handoff

Review Standards and Spec separately against fixed base/head. Check no private imports or unnecessary dependencies, source identity, Git safety, completeness, copy semantics, and full-versus-filtered visibility. Label author review as self-review. Preserve the comparison model for later reuse without claiming unimplemented providers. Requirements: [FILTERS_AND_DIFFS.md](../FILTERS_AND_DIFFS.md). Dependency decisions and engineering gates: [DIFF_ENGINEERING.md](../DIFF_ENGINEERING.md).
