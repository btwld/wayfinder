# W02 — Extract the runtime into a supported Wayfinder SDK

**Batch:** A  
**Status:** ready-for-agent  
**Blocked by:** W01  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

The existing CLI/MCP and a direct Dart consumer invoke one reusable runtime through public SDK imports. Executable-specific asset discovery remains in the CLI adapter.

## Scope

- Add the SDK to the Dart workspace, with public exports, package documentation, and repository-consistent licensing.
- Move the shared knowledge coordination and its tests, including the generated search contract, to the owning SDK.
- Inject actual resource-opening/location behavior. Keep terminal output, process exit, install/update, and MCP registration in the adapter.
- Migrate production consumers without a duplicate runtime. Use expand/migrate/contract only where needed to keep intermediate checks green.

## Acceptance criteria

- [ ] CLI and MCP command/tool names, arguments, defaults, JSON/text envelopes, and failure mapping remain compatible.
- [ ] Dense mode, freshness refusal, locking, resource lifetime, and generation publication behavior are not silently redesigned.
- [ ] A direct deterministic Dart example resolves resources through explicit configuration and uses only public imports.
- [ ] All production cross-package imports of another package’s private src implementation are removed from the migrated path.
- [ ] Existing source-nonmutation, inference-failure, generation, and resource-close behavior tests still pass or have an explicit environment blocker.
- [ ] The SDK has no Flutter or MCP dependency; native-retrieval dependencies are accurately documented rather than claimed absent.

## Out of scope and external gates

Do not fix #110 or #45, add a new database, or add a wrapper class for every upstream type.

## Test and demonstration evidence

Move behavior tests with ownership. Verify the old adapters and the direct consumer through the same implementation. Inspect the extraction diff for accidental storage schema churn.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
