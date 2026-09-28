# W05 — Add explicit retrieval session ownership

**Batch:** B  
**Status:** planned  
**Blocked by:** W03  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A long-lived caller can reuse retrieval resources without reopening the model for every request and can close safely under failure or cancellation.

## Scope

- Introduce the smallest session interface justified by CLI and desktop consumers.
- Define owned/borrowed dependencies, lazy loading, operation progress, and idempotent close.
- Preserve explicit retrieval modes and maintain command-oriented adapters where required.

## Acceptance criteria

- [ ] Resource-open counts prove reuse in a session and final release after close.
- [ ] Borrowed resources are not disposed accidentally; owned resources close once on success/failure.
- [ ] Repeated close, cancellation, failed inference, and close during an active request have deterministic results.
- [ ] The UI can identify obsolete request completions; heavy work does not require running on its isolate.
- [ ] Public CLI/MCP behavior changes, if any, are separately documented and tested.

## Out of scope and external gates

Do not mix this task with multi-process reader leases or a storage-engine replacement.

## Test and demonstration evidence

Use deterministic resource adapters to count opens/closes and inject failures. Exercise the public session interface.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
