# Wayfinder adjustment pack

Start with [ADJUSTMENT.md](ADJUSTMENT.md). The [Batch A execution specification](../wayfinder-sdk-batch-a.md) remains the controlling assignment: **W01 → W02 → W03**.

[WORKBENCH.md](WORKBENCH.md) now specifies the Remix Vanilla dashboard_shell and a searchable Wayfinder companion. Its first complete outcome includes semantic search, concept-type filtering, validation, and source/passage/index inspection. A smaller read-only bootstrap remains useful but is not the complete workbench.

The workbench sequence is WB01 (shell/read/validate), W08 after W03 (public filtered search and inspection), then WB02 (integrated search). These three items are planned, not activated or completed. They do not require Super Editor or search-during-refresh to begin delivering value.

| Document | Purpose |
| --- | --- |
| [Workbench plan](WORKBENCH.md) | Dashboard shell, current source pins, search and type semantics, index diagnostics, and acceptance. |
| [Execution brief](EXECUTE_BATCH_A.md) | Batch A implementation entry point and stop conditions. |
| [Review brief](REVIEW.md) | Fixed-base Standards and Spec review. |
| [Tickets](tickets/) | Fifteen individual work items with blockers and acceptance criteria. |
| [Task manifest](task-manifest.json) | Machine-readable batches and dependencies, including the planned workbench track. |
| [Report template](IMPLEMENTATION_REPORT_TEMPLATE.md) | Evidence format, not a completed report. |
| [Status](STATUS.md) | Actual execution and verification state. |
| [Plan checker](tools/check_plan.py) | Structural checks, not application verification. |

Ticket acceptance lives in the individual files; keep their metadata, this plan, and the manifest aligned. Existing F01–F03 cover later editing/product integration. Reuse the workbench's shared search behavior rather than implement another engine.

No implementation, release, merge, or change to real knowledge files occurred through this planning update. Later batches do not start automatically.

```sh
python3 tools/check_plan.py
```

A structural pass does not establish Dart generation, Flutter behavior, native compatibility, relevance quality, or independent code review.
