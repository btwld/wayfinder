# W07 — Prepare and commit reviewed Profile-aware changes

**Batch:** B  
**Status:** planned  
**Blocked by:** W04  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A caller previews a structured concept change, sees its exact navigation/log consequences, and commits only the same validated candidate against unchanged source revisions.

## Scope

- Re-read issue #45 and resolve the narrow generic-versus-Concepta projection ownership decision.
- Prefer existing generic write machinery with a proven extension seam; record an upstream proposal if required rather than changing another repository.
- Validate OKF and the applicable Profile on the exact candidate; separate preparation, review, and commit.

## Acceptance criteria

- [ ] Create/update/link/deprecate fixtures use the required projection and do not substitute generic output for Profile output.
- [ ] Candidate content and revisions bind the commit; replaying a reviewed token against different content is refused.
- [ ] A failing gate or external edit leaves the intended source set unchanged, with recoverable evidence for partial I/O failure.
- [ ] No-op changes do not regenerate navigation or append log entries.
- [ ] The report separates rollback guarantees from crash-atomicity limitations and leaves judgment rules unassessed.
- [ ] Ordinary source-save behavior remains independent from the conformant structured operation.

## Out of scope and external gates

Do not implement a generic Profile provider platform, alter real bundles, or close #45 automatically.

## Test and demonstration evidence

Test through prepare/commit with golden projections, expected revisions, injected I/O failures, and source-byte checks.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
