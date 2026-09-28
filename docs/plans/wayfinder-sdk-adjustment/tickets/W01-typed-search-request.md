# W01 — Use AckInfer for the existing search request

**Batch:** A  
**Status:** ready-for-agent  
**Blocked by:** None — can start immediately  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A CLI or MCP search request follows the existing validation/default contract but is consumed through a generated typed value. The operation rejects invalid directly constructed values as well as invalid decoded inputs.

## Scope

- Record baseline request/schema and handler behavior before replacing map access.
- Introduce AckInfer and real generated output for the existing search request; retain the established query and limit contract.
- Use typed access in both CLI and MCP paths without changing their external shape.
- Resolve all build/analyzer constraints with existing workspace generators; document exact versions.

## Acceptance criteria

- [ ] Default limit is 5; limits 1 and 100 pass and out-of-range values fail as before.
- [ ] Missing/blank/Unicode-whitespace queries, wrong types, explicit null, and unknown keys match characterized baseline behavior.
- [ ] Both adapters reach the same validated behavior; invalid direct model construction cannot bypass operation checks.
- [ ] MCP JSON Schema and public error/output conventions are unchanged.
- [ ] The builder produces checked-in outputs; no generated file is written by hand; narrow tests pass.

## Out of scope and external gates

Do not redesign graph requests, authoring schemas, search modes, or the entire domain model.

## Test and demonstration evidence

Use existing Ack input and CLI/MCP request tests as the starting seam. Show one unchanged happy path and one rejected request through each adapter.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
