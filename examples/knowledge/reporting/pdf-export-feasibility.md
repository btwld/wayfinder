---
type: Analysis
title: PDF export feasibility for annotations
description: Whether the current renderer can place annotations without exceeding the generation budget.
status: draft
generated: { by: claude-code/opus-5, at: 2026-07-31T11:00:00Z }
stale_after: 2026-11-01
sources:
  - id: layout-sample
    resource: /references/annotation-layout.json
    title: Exported annotation layout sample
---

# Question

Can annotations be positioned in the exported PDF within the existing
generation budget? This analysis applies to the current renderer contract
through 31 October 2026; the contract changes on 1 November.

# Findings

The renderer exposes absolute placement; annotation geometry is already
persisted alongside review state.[^layout-sample]

# Recommendation

Proceed. Budget headroom is adequate at current document sizes.

# Relationships

- Refines: [Include PDF annotations in the export](/reporting/include-pdf-annotations.md)
- Constrained by: [Pagination contract](/reporting/pagination-contract.md)

[^layout-sample]: Exported annotation layout sample
