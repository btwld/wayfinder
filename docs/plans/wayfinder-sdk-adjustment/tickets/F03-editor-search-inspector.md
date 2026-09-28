# F03 — Integrate search, diagnostics, and related-document navigation

**Batch:** C  
**Status:** planned  
**Blocked by:** F02, W06  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A user finds saved documents, follows revision-aware search hits, and reads metadata/diagnostics/backlinks without blocking typing or confusing stale hits with current source.

## Scope

- Use the shared SDK for retrieval and validation; derive navigation from upstream OKF meanings.
- Keep title/path lookup responsive without a semantic model and label lexical fallback clearly.
- Present refresh progress, unavailable resources, unsupported Profile, and stale citations as distinct states.

## Acceptance criteria

- [ ] Saving queues derived refresh without making a successful source save depend on index success.
- [ ] Obsolete searches cannot replace a newer query result; current-file navigation checks hit revisions.
- [ ] Index rebuild/clear leaves recovery untouched; no private CLI imports or duplicate primary search engine appear.
- [ ] Inspector updates do not compete with source mode; unknown fields survive edits.
- [ ] Model unavailable, first index, refresh failure, external file change, and large-folder behavior are demonstrated.

## Out of scope and external gates

Do not add a graph UI, semantic answer generator, or silently index raw captures.

## Test and demonstration evidence

Use the app workflow plus SDK fixtures for stale/fresh/refreshing states and indexed-versus-current source locations.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
