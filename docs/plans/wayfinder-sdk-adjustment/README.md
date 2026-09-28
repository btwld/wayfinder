# Wayfinder adjustment pack

Start with [ADJUSTMENT.md](ADJUSTMENT.md) for the architecture and package decisions. The existing [Batch A execution specification](../wayfinder-sdk-batch-a.md) remains the controlling scope for the first implementation session: **W01 → W02 → W03**.

For the smallest useful desktop app, read [Wayfinder Workbench](WORKBENCH.md). It proposes Remix beta.10 with the Vanilla preset and a folder-to-validation workflow. A read-only diagnostic app can consume the existing public OKF/Profile libraries without waiting for the SDK or installing an embedding model. This is a companion proposal, not an implemented app or an automatic activation of later tickets.

| Document | Purpose |
| --- | --- |
| [Workbench review](WORKBENCH.md) | Minimal Flutter app, current Remix setup, validation/debug behavior, and acceptance tests. |
| [Execution brief](EXECUTE_BATCH_A.md) | Implementer entry point and stop conditions. |
| [Review brief](REVIEW.md) | Fixed-base Standards and Spec review. |
| [Tickets](tickets/) | Twelve individual work items with blockers and acceptance criteria. |
| [Task manifest](task-manifest.json) | Machine-readable batches and dependency edges. |
| [Report template](IMPLEMENTATION_REPORT_TEMPLATE.md) | Evidence format for later implementation; not a completed report. |
| [Status](STATUS.md) | Actual execution and verification state. |
| [Plan checker](tools/check_plan.py) | Structural checks for ticket identity, dependencies, metadata, and links. |

Ticket bodies live once in `tickets/`. The adjustment document links to them instead of duplicating their full contents. Keep ticket metadata and the manifest aligned.

Batch A readiness does not mean execution occurred. Batches B/C and optional work remain planned or gated. No new Flutter repository, package release, merge, or change to real knowledge files is authorized by this planning PR.

Run the structural checker from this directory with:

```sh
python3 tools/check_plan.py
```

A structural pass is not Dart generation, application testing, native verification, or independent code review.
