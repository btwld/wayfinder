---
type: Guide
title: Flutter adaptive layouts
description: How to choose responsive widget trees from available window constraints.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T17:39:20Z }
sources:
  - id: flutter-responsive-skill
    resource: https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-build-responsive-layout/SKILL.md
    title: flutter-build-responsive-layout skill
  - id: flutter-architecture-overview
    resource: https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/resources/architectural-overview.md
    title: Flutter architectural overview
---

# Guidance

Choose an adaptive widget tree from the space the app window actually receives.
Use `LayoutBuilder` for a parent allocation and `MediaQuery.sizeOf` for the
whole app window. Breakpoints should be based on available width, not a guessed
phone/tablet category or device orientation. `Expanded` and `Flexible` distribute
space inside a flex, while `ConstrainedBox` prevents content from stretching
without limit on large windows.

The responsive skill also calls for lazy builders for large collections and
supports keyboard, mouse, trackpad, and touch input. These are implementation
choices to evaluate for the target app, not proof that one breakpoint fits all
products.[^flutter-responsive-skill] [^flutter-architecture-overview]

[^flutter-responsive-skill]: [flutter-build-responsive-layout skill](https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-build-responsive-layout/SKILL.md)
[^flutter-architecture-overview]: [Flutter architectural overview](https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/resources/architectural-overview.md)
