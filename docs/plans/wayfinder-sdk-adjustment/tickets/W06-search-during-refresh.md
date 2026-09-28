# W06 — Serve pinned completed generations during refresh

**Batch:** B  
**Status:** planned  
**Blocked by:** W05  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

An opted-in caller can search the last completed generation while a writer refreshes it, with explicit revision and freshness information. Strict callers retain current-only behavior.

## Scope

- Re-read issue #110 and its comments; preserve one writer while enabling safe completed-generation readers.
- Add cross-process generation leases and cleanup ordering, not just an in-memory reference count.
- Introduce explicit requireCurrent/allowLastCompleted policy and revision-bearing results.
- Define no-index, refreshing, stale, fresh, failed-refresh, and obsolete-citation behavior.

## Acceptance criteria

- [ ] A separate-process reader returns a completed generation during indexing without accessing partial or deleted files.
- [ ] Two writers do not publish conflicting generations.
- [ ] Default strict calls refuse stale data as before; opted-in results carry generation/source revision and a notice.
- [ ] A first build reports no available generation instead of presenting empty results as a successful search.
- [ ] Writer failure retains the previous committed generation; interrupted readers do not cause permanent leaks or unsafe deletion.
- [ ] Citations remain tied to the indexed revision; current-file navigation checks divergence.
- [ ] Any added CLI/MCP option is additive and covered by compatibility tests.

## Out of scope and external gates

Do not close #110 automatically or remove safety checks to avoid a busy error.

## Test and demonstration evidence

Use real subprocess race tests for writer exclusion, publication, lease acquisition, crash, and reclamation. Single-isolate mocks alone are insufficient.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
