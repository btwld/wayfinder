# W03 — Verify regeneration, independent consumption, and the extraction

**Batch:** A  
**Status:** ready-for-agent  
**Blocked by:** W02  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A maintainer can reproduce generation, consume the SDK outside the monorepo, and review an evidence-backed Batch A change without relying on an agent’s success claim.

## Scope

- Extend generation and validation entry points for the SDK while preserving ObjectBox generation.
- Exercise a temporary consumer outside workspace resolution; do not let local overrides conceal a broken package manifest.
- Run available native integration checks and record missing assets/platforms as blocked or skipped.
- Review the fixed base/head on Standards and Spec, fix in-scope findings, and write the implementation report.

## Acceptance criteria

- [ ] Dependency resolution succeeds for the selected supported toolchain or the exact incompatibility is recorded.
- [ ] Two successive generation runs are stable; git status catches untracked ignored outputs as well as tracked diffs.
- [ ] Analyze, format, targeted tests, and available full tests have recorded commands and results.
- [ ] Independent consumer public imports and deterministic search/runtime smoke tests succeed.
- [ ] No ObjectBox schema/model-ID changes or package publication are introduced unintentionally.
- [ ] Base/head, completed tickets, pass/fail/skip counts, platform gaps, and both review axes are documented.
- [ ] Any independent review is distinguishable from self-review; the batch is not declared release-ready while required evidence is missing.

## Out of scope and external gates

Do not publish, tag, merge, or continue into later batches.

## Test and demonstration evidence

Use repository validation scripts plus a clean regeneration check and the external consumer. Package dry-run checks do not authorize release.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
