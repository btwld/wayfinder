# F01 — Open, source-edit, validate, and safely save a local file

**Batch:** C  
**Status:** blocked-external  
**Blocked by:** W03, W04  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

In the selected Flutter application repository, a user opens a folder, edits a Markdown file, previews diagnostics, saves, and reopens it without losing source or unsaved work.

## Scope

- Use a single app package with an application coordinator, source-preserving document session, recovery, and public SDK adapter.
- Keep plain Markdown, generic OKF, and Profile modes distinct.
- Support explicit save, external-change conflicts, revisioned completions, and recovery separate from caches.

## Acceptance criteria

- [ ] An unedited file is byte-identical after open/close; metadata-only and body-only edits preserve untouched regions.
- [ ] Unknown frontmatter, line endings, source-only constructs, read-only files, and failed writes are covered.
- [ ] External changes conflict instead of overwriting dirty edits; old save completions do not clear new changes.
- [ ] Validation preview does not write; incomplete source can be saved without a false conformance claim.
- [ ] Workspace path escape and symlink behavior are explicit and tested; no remote content is fetched automatically.

## Out of scope and external gates

External gate: an application repository and target platform must be selected. Do not create a product repository in this Wayfinder batch.

## Test and demonstration evidence

Exercise a real temporary-folder workflow through the app/session interface with synthetic fixtures and I/O failure injection.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
