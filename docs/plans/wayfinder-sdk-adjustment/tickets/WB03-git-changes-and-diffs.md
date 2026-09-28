# WB03 — Inspect local Git changes with explicit comparison sides

**Batch:** workbench
**Status:** planned
**Blocked by:** WB01

## What to build

A person opens a local folder in the workbench, filters its changed files, selects staged or unstaged changes, and reads a correctly labeled source diff without modifying the repository. Git is optional; Library and Validation remain useful without it.

## Scope

Add a Changes destination to the existing Remix dashboard shell. Use a small read-only local Git process adapter and native Flutter unified diff presentation. Keep the complete comparison model independent of layout so a later side-by-side view, saved-buffer comparison, and indexed-source comparison can reuse it. Do not install the full Remix dashboard demo or build another design system.

Discover the repository/worktree correctly, restrict visible paths to the selected root, parse machine-readable NUL-delimited records, and retain both paths of a rename. Name old/new sources and capture their revisions or hashes. Keep staged, unstaged, and untracked groups separate. Respect the process/configuration/attribute policy in the companion plan; read-only commands are not automatically safe against repository-configured helpers.

## Acceptance criteria

- [ ] Open → Changes → filter → select file → read unified diff works against a real synthetic Git repository using public app behavior.
- [ ] Active filters are visible, removable, and resettable; shown versus total counts are truthful; returning from a diff preserves filter and selection state.
- [ ] Unstaged compares staging index to working tree; staged compares pinned HEAD to staging index; untracked compares absent to saved source. One file can appear in both staged and unstaged groups.
- [ ] Diff rows preserve old/new line numbers, additions/removals/context, final-newline markers, and explicit whitespace/line-ending policy. A Markdown preview is not the diff authority.
- [ ] Root discovery supports a selected subfolder and worktree; out-of-scope rename sides, symlinks, and submodule contents are not read to fill missing context.
- [ ] Added/deleted/renamed files, unusual path bytes, unborn/detached HEAD, conflicts, binary/mode-only changes, and missing objects produce correct results or explicit unsupported states, never false clean results.
- [ ] Git missing, non-repository folder, policy-blocked repository, no changes, stale observation, and operation failure remain distinct. Other destinations remain usable.
- [ ] Git commands use approved argument arrays, bounded streams/timeouts, tested helper/configuration controls, no network access, and no shell interpolation. Unsupported external-filter repositories fail closed under the documented policy.
- [ ] Refresh/view/filter/copy leave source bytes, the Git staging index, refs, and configuration unchanged. No staging, committing, resetting, applying, or downloading is exposed.
- [ ] Large or incomplete diffs visibly disclose limits. A local Viewed marker, if included, is content-specific and cannot imply hidden or partial changes were reviewed.
- [ ] Keyboard navigation, selection/copy, light/dark appearance, narrow layout, late-request rejection, and source non-mutation are tested on the declared desktop target.

## Out of scope and external gates

Not part of active W01–W03. No GitHub account/remote integration, history browser, stage/commit controls, conflict resolution, Git installation, new storage engine, or public diff library. Super Editor, native embeddings, W06, and WB02 are not prerequisites. Saved-buffer and indexed-source comparisons require their actual source providers before being enabled. Side-by-side and intraline decoration may follow the verified unified workflow.

## Test and demonstration evidence

Use synthetic repositories, including a file staged and then edited again, a deleted file, a rename, an untracked Unicode/control-character filename, a changed file outside the selected root, CRLF/final-newline cases, and an external-helper trap. Compare both sources explicitly, hash repository/source state around reads, and inspect exact command outputs and exit codes. The earlier 11-check Git experiment is preliminary CLI evidence, not completion of this ticket. Record package/toolchain choices, runtime checks, unsupported cases, and skips.

## Review and handoff

Review Standards and Spec separately against fixed base/head. Check filesystem/process containment, no write paths, source identity, diff completeness, and full-versus-filtered visibility. Preserve the comparison model for later source/buffer and index/current reuse without adding those unimplemented features. Detailed requirements and package research: [FILTERS_AND_DIFFS.md](../FILTERS_AND_DIFFS.md).
