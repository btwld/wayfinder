# Reviewer brief — fixed-point review

Read ADJUSTMENT.md, the three Batch A tickets, repository standards, and the implementation report. Resolve and record exact base/head SHAs. Review the diff from their merge base and verify the commit list. Do not review a moving working tree or treat an empty diff as a completed implementation.

## Standards

Check repository instructions, ownership, dependency direction, public imports, resource lifetime, native packaging, and generated-file policy. Treat generic code smells as judgments, not violations. Inspect duplication, excessive wrappers, speculative abstractions, and mixed CLI/runtime responsibilities. Do not repeat formatting/lint output as substantive review.

## Spec

For each acceptance criterion, identify test evidence or a missing/partial behavior. Concentrate on search-input semantics, invalid direct constructors, CLI/MCP JSON Schema and error compatibility, source non-mutation, generator reproducibility, consumer resolution, and unchanged storage identities. Flag later-batch behavior changes as scope creep.

## Reporting

Keep Standards and Spec findings separate. Each finding names severity, file/line, evidence, impact, and the smallest in-scope remedy. Record commands actually rerun and missing native/platform coverage. Do not convert a passed static check into a runtime guarantee. Do not edit code or merge. If the author changes the head, rerun affected review against the new head.

An independently launched reviewer must identify itself and the reviewed SHA. If the implementer performs both passes, the report must say self-review, not independent review.
