---
type: Guide
title: Flutter layout constraints
description: Diagnosing common unbounded-constraint and overflow errors.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T01:20:47Z }
sources:
  - id: flutter-layout-fix-skill
    resource: https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-fix-layout-issues/SKILL.md
    title: flutter-fix-layout-issues skill
  - id: flutter-responsive-constraints
    resource: https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-build-responsive-layout/SKILL.md
    title: responsive layout constraints guidance
---

# Diagnosis and fixes

Flutter layout follows “constraints go down, sizes go up, parent sets position.”
A scrollable in a `Column` can receive unbounded height; a text field in a
`Row` can receive unbounded width; and a `Row` or `Column` can overflow when a
child asks for more than its allocation. `RenderBox was not laid out` is often a
secondary error, so inspect the earlier constraint exception first.

Choose a fix from the actual parent constraints: put a scrollable in `Expanded`
or give it a bounded `SizedBox`; use `Expanded` or `Flexible` for a field or
other child that must share a flex allocation; and keep `Expanded`, `Flexible`,
and `Positioned` under the parent types that consume their parent data. Re-run
the app and inspect the primary error after each change.[^layout-fix]

[^layout-fix]: flutter-fix-layout-issues skill
