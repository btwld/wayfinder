# W04 — Validate unsaved candidates without writing

**Batch:** B  
**Status:** planned  
**Blocked by:** W02  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A caller previews OKF/Profile findings for source edits using the same owning rules as file-based validation, without changing disk content.

## Scope

- Add a candidate validation entry point in the existing Profile owner and delegate equivalent disk checks to it.
- Carry candidate source revision, logical paths, assets, and loader diagnostics explicitly.
- Preserve generic-OKF versus declared-Profile behavior and unsupported-release outcomes.

## Acceptance criteria

- [ ] Equivalent candidates and on-disk bundles produce equivalent applicable findings.
- [ ] Validation preview makes no source, index, or log writes.
- [ ] Unknown metadata is preserved, not filtered through a closed generated schema.
- [ ] Malformed source, absent Profile declaration, unsupported Profile, and unassessed judgment have distinct results.
- [ ] The response identifies which candidate was checked and which filesystem checks were not performed.

## Out of scope and external gates

Do not add a general Profile plug-in registry or require valid source before saving.

## Test and demonstration evidence

Use synthetic candidate fixtures and the public validator. Add paired disk/in-memory tests and snapshot source bytes before and after.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
