# Implementer brief — Batch A

Read ADJUSTMENT.md first. It contains the scope, evidence, tests, and complete work items. Use tickets/W01-typed-search-request.md, tickets/W02-extract-sdk.md, and tickets/W03-verify-sdk-batch.md in that order. Later work is not assigned to this session.

Work only in an isolated branch of btwld/wayfinder. Read its AGENTS.md and relevant standards/ADRs. Verify the recorded base. Preserve unrelated changes; do not modify main, force-push, merge, publish, or close existing issues.

Run baseline checks where available. Implement one testable behavior at a time. Generate Ack output using the actual builder. Keep CLI/MCP wire behavior, current search policy, index storage, and source non-mutation intact. Expose one shared SDK implementation and exercise a direct consumer without private imports.

Complete the clean regeneration, dependency, consumer, and available native checks. Separate failures and skips from passes. Review both Standards and Spec against fixed base/head. Label a self-review as such. Use IMPLEMENTATION_REPORT_TEMPLATE.md, include remaining blockers, and stop after Batch A. A draft PR is permitted; a release is not.
