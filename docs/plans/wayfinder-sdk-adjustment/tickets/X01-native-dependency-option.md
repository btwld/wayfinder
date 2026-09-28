# X01 — Prove and, if needed, separate lightweight retrieval packaging

**Batch:** optional  
**Status:** deferred  
**Blocked by:** W03  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A demonstrated minimal distribution can use lexical retrieval without resolving or bundling unwanted native retrieval implementation dependencies.

## Scope

- Measure the actual dependency and asset graph from an independent consumer.
- Activate a native-package split only after a specific distribution requirement is accepted.
- Preserve public-contract ownership and document the migration for any moved imports.

## Acceptance criteria

- [ ] Before/after dependency and asset lists substantiate the need and the outcome.
- [ ] Lexical and native consumers both resolve and run their respective smoke tests.
- [ ] No native-free claim relies only on not loading a model at runtime.
- [ ] Supported native configurations and storage compatibility remain verified; license notices are retained.

## Out of scope and external gates

Activation gate: a concrete lightweight-distribution requirement. This is not part of Batch A.

## Test and demonstration evidence

Use isolated consumer manifests and built-asset inspection, not only source-import grep.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
