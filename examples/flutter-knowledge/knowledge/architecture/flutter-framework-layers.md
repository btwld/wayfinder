---
type: Architecture Document
title: Flutter framework layers
description: How widgets, elements, render objects, and the rendering pipeline relate.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T17:39:20Z }
sources:
  - id: flutter-architecture-overview
    resource: https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/resources/architectural-overview.md
    title: Flutter architectural overview
  - id: flutter-inside
    resource: https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/resources/inside-flutter.md
    title: Inside Flutter
---

# Model

Flutter is layered: a platform embedder integrates with the operating system,
the engine provides low-level graphics and runtime services, and the Dart
framework provides foundation, rendering, widgets, and Material or Cupertino
packages. The rendering layer builds renderable objects; the widgets layer
composes immutable configuration into an element tree that retains relationships
and state.

During layout, constraints move from parent to child and geometry returns to the
parent. During build, dirty elements are revisited while clean subtrees can be
skipped. These are framework implementation properties described by the sources,
not a promise that every application has a particular performance profile.[^flutter-architecture-overview]
[^flutter-inside]

[^flutter-architecture-overview]: [Flutter architectural overview](https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/resources/architectural-overview.md)
[^flutter-inside]: [Inside Flutter](https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/resources/inside-flutter.md)
