---
type: Analysis
title: PDF export feasibility for annotations
description: Whether the current renderer can place annotations without exceeding the generation budget.
status: draft
generated: { by: claude-code/opus-5, at: 2026-07-31T11:00:00Z }
stale_after: 2026-10-31
---

# Question

Can annotations be positioned in the exported PDF within the existing
generation budget?

# Findings

The renderer exposes absolute placement; annotation geometry is already
persisted alongside review state.

# Recommendation

Proceed. Budget headroom is adequate at current document sizes.

# Relationships

- Refines: [Include PDF annotations in the export](/include-pdf-annotations.md)
