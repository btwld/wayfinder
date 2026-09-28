# WB01 — Open and validate a folder in the Remix dashboard shell

**Batch:** workbench
**Status:** planned
**Blocked by:** None

## What to build

A person opens an explicit local folder in a small desktop workbench, reads Markdown even when malformed, validates saved files, and follows a finding back to its source. The app uses the installed Remix dashboard_shell and Vanilla preset instead of a custom shell.

## Scope

Create the proposed independent Flutter reference app in the Wayfinder repository without changing root Dart-only workspace requirements. Pin and record the tested runtime, CLI, registry, and lockfile. Install dashboard_shell rather than dashboard_demo. Compose Library, Search, Validation, and Index destinations; until retrieval is implemented, Search/Index show explicit capability-unavailable states rather than fake results. Keep account UI and unused shell search absent. Use public OKF/Profile libraries for read-only browsing and validation.

Preserve the original folder-selection, invalid-source, scope, source-containment, theme, overlay, diagnostics, and export rules in the Workbench specification. This is a useful bootstrap, not the complete searchable workbench.

## Acceptance criteria

- [ ] Installed Vanilla shell, real registry pin, and generation output resolve and render on the stated desktop target; no showcase/sample-data dependency is installed unnecessarily.
- [ ] Open/cancel/change folder works; the selected root remains visible and no late response overwrites a newer root's state.
- [ ] Plain Markdown, valid OKF, malformed frontmatter, missing files, and access errors produce appropriate readable states.
- [ ] Auto/OKF/Profile validation preserves equivalent owning-library findings and unassessed judgment rules; malformed Profile declarations cannot silently pass.
- [ ] Located and path-only findings navigate without invented locations; results become visibly outdated after source changes.
- [ ] Source-tree bytes are unchanged by reading, preview, validation, and export.
- [ ] Default diagnostics stay local/redacted; no automatic downloads, remote resource fetches, or Markdown execution occur.
- [ ] Keyboard focus, overlays, narrow layout, text scaling, light/dark mode, and model-free validation are demonstrated.
- [ ] Independent Flutter checks do not silently add a Flutter requirement to the root Dart workflow.

## Out of scope and external gates

No SDK extraction prerequisite for this bootstrap. Flutter/toolchain/registry resolution must actually pass. Semantic search, source editing, Super Editor, a second repository, account features, charts, and publication are not in this slice. Preserve W01–W03 as the active assigned batch unless the user separately activates this work.

## Test and demonstration evidence

Run the full folder-to-finding workflow on authorized fixtures, snapshot source bytes before/after, test folder-change races, and compare validation results with direct library calls. Record platform, package pins, regeneration result, Flutter checks, and unavailable evidence.

## Review and handoff

Review Standards for actual template reuse and SDK independence; review Spec for the full read/validate/navigation behavior. Hand off the working shell to WB02. Use [WORKBENCH.md](../WORKBENCH.md), not an invented preset API.
