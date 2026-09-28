# Wayfinder adjustment pack

Start with [ADJUSTMENT.md](ADJUSTMENT.md). The [Batch A execution specification](../wayfinder-sdk-batch-a.md) remains the controlling assignment: **W01 → W02 → W03**.

[WORKBENCH.md](WORKBENCH.md) specifies the Remix Vanilla dashboard_shell and a searchable Wayfinder companion. Its first complete searchable outcome includes semantic search, concept-type filtering, validation, and source/passage/index inspection. A smaller read-only bootstrap remains useful but is not the complete searchable workbench.

[FILTERS_AND_DIFFS.md](FILTERS_AND_DIFFS.md) adds visible applied filters, truthful counts, a read-only local Git Changes destination, explicit comparison sides, native diff presentation, process safety, and package research. Git is optional and independent of the search engine. The GitHub connector used to update the plan is not a runtime dependency of the app.

The workbench sequence is WB01 (shell/read/validate), W08 after W03 (public filtered search and inspection), then WB02 (integrated search). WB03 (read-only Git review) branches from WB01 and does not wait for search or Super Editor. These items are planned, not activated or completed.

| Document | Purpose |
| --- | --- |
| [Workbench plan](WORKBENCH.md) | Dashboard shell, source pins, search/type semantics, index diagnostics, and acceptance. |
| [Filters and diffs](FILTERS_AND_DIFFS.md) | Applied-filter visibility, Changes page, comparison identity, correct rendering, Git safety, and package research. |
| [Execution brief](EXECUTE_BATCH_A.md) | Batch A implementation entry point and stop conditions. |
| [Review brief](REVIEW.md) | Fixed-base Standards and Spec review. |
| [Tickets](tickets/) | Sixteen individual work items with blockers and acceptance criteria. |
| [Task manifest](task-manifest.json) | Machine-readable batches and dependencies, including the planned workbench track. |
| [Report template](IMPLEMENTATION_REPORT_TEMPLATE.md) | Evidence format, not a completed report. |
| [Status](STATUS.md) | Actual execution and verification state. |
| [Plan checker](tools/check_plan.py) | Structural checks, not application verification. |

Ticket acceptance lives in the individual files; keep metadata, companion plans, and the manifest aligned. Existing F01–F03 cover later editing/product integration. Reuse shared search and comparison behavior rather than implement another engine. The filter/diff companion controls those additions; it does not change the behavior-preserving Batch A scope.

No implementation, release, merge, or change to real knowledge files occurred through this planning update. Later batches do not start automatically.

```sh
python3 tools/check_plan.py
```

A structural pass does not establish Dart generation, Flutter behavior, native compatibility, relevance quality, or independent code review. Synthetic Git CLI checks are separate from the still-unimplemented app and its adapter.
