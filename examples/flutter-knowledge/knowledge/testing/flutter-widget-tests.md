---
type: Guide
title: Flutter widget tests
description: A WidgetTester workflow for rendering and interaction tests.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T17:39:20Z }
sources:
  - id: flutter-widget-skill
    resource: https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-add-widget-test/SKILL.md
    title: flutter-add-widget-test skill
---

# Guidance

Put widget tests in `test/` with a `_test.dart` suffix and use
`flutter_test`. Build the widget with `pumpWidget`, wrap it in the inherited
widgets it needs, locate elements with `Finder`, and assert the initial state.
After taps or text entry, call `pump` for a frame or `pumpAndSettle` for an
animation before asserting the new state. Scroll long lists until the target is
visible rather than assuming it is mounted.

Widget tests exercise a widget tree. They complement Dart unit tests; this
concept does not replace the package-level testing guidance.[^flutter-widget-skill]

[^flutter-widget-skill]: [flutter-add-widget-test skill](https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-add-widget-test/SKILL.md)
