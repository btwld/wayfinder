# Wayfinder adjustment pack

Start with [ADJUSTMENT.md](ADJUSTMENT.md). The [Batch A execution specification](../wayfinder-sdk-batch-a.md) remains the controlling assignment: **W01 → W02 → W03**.

[WORKBENCH.md](WORKBENCH.md) specifies the Remix Vanilla dashboard_shell and a searchable Wayfinder companion. Its first complete searchable outcome includes semantic search, concept-type filtering, validation, and source/passage/index inspection. A smaller read-only bootstrap is not the complete searchable workbench.

[FILTERS_AND_DIFFS.md](FILTERS_AND_DIFFS.md) specifies visible applied filters, truthful counts, optional read-only Git Changes, explicit comparison sides, and process safety. [DIFF_ENGINEERING.md](DIFF_ENGINEERING.md), revision 6, supersedes its package preference order and makes the implementation concrete: Git-produced comparisons, an immutable application model, a public-API Re-Editor renderer experiment, and conditional browser alternatives. Older text-diff widgets are not default dependencies. All original read-only, containment, source-preservation, and filter semantics remain in force.

The workbench sequence is WB01 (shell/read/validate), W08 after W03 (public filtered search and inspection), then WB02 (integrated search). WB03 (read-only Git review) branches from WB01 and does not wait for search or Super Editor. These items remain planned, not activated or completed. Git is optional; the GitHub connector used to maintain this plan is not an application runtime dependency.

| Document | Purpose |
| --- | --- |
| [Workbench plan](WORKBENCH.md) | Dashboard shell, source pins, search/type semantics, index diagnostics, and acceptance. |
| [Filters and diffs](FILTERS_AND_DIFFS.md) | Filter visibility, comparison identity, Changes behavior, and read-only Git policy. |
| [Diff engineering](DIFF_ENGINEERING.md) | Updated maintenance review, renderer/algorithm separation, comparison model, and implementation gates. |
| [Execution brief](EXECUTE_BATCH_A.md) | Batch A implementation entry point and stop conditions. |
| [Review brief](REVIEW.md) | Fixed-base Standards and Spec review. |
| [Tickets](tickets/) | Sixteen individual work items with blockers and acceptance criteria. |
| [Task manifest](task-manifest.json) | Machine-readable batches and dependencies; unchanged by revision 6. |
| [Report template](IMPLEMENTATION_REPORT_TEMPLATE.md) | Evidence format, not a completed report. |
| [Status](STATUS.md) | Actual execution and verification state. |
| [Plan checker](tools/check_plan.py) | Structural checks, not application verification. |

Ticket acceptance lives in the individual files; keep metadata and companion plans aligned. F01–F03 cover later editing/product integration. Reuse established search and comparison behavior, not a second engine. WB03 now includes the selection/copy and parser-correctness gates without changing its ID, title, blocker, or planned state.

No application implementation, release, merge, real knowledge-file modification, or new agent execution is implied by this planning update. Later batches do not start automatically.

```sh
python3 tools/check_plan.py
```

A structural pass does not establish Dart generation, Flutter behavior, native compatibility, relevance quality, or independent review. A synthetic Git command test is not an application or renderer test.
