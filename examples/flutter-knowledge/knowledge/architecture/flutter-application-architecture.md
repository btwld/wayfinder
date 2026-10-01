---
type: Architecture Document
title: Flutter application architecture
description: Conditional UI, data, and domain boundaries for Flutter applications.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T01:20:47Z }
sources:
  - id: flutter-architecture-skill
    resource: https://github.com/flutter/agent-plugins/blob/8da8c54ecd740fded70f908ad9c46b72a1f21fb5/skills/flutter-apply-architecture-best-practices/SKILL.md
    title: flutter-apply-architecture-best-practices skill
  - id: flutter-architecture-concepts
    resource: https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/app-architecture/concepts.md
    title: Flutter common architecture concepts
---

# Boundaries

Separate the UI, data, and optional logic layers. UI widgets should stay lean
and render state exposed by a view model. Services wrap external systems;
repositories provide a single source of truth and map external models to domain
models. Add a use-case or domain layer when business logic is complex or reused
across view models. Simple CRUD applications may not need that layer.

The Flutter documentation describes layering, separation of concerns, single
source of truth, and unidirectional data flow. The agent skill adds a concrete
MVVM and repository workflow. The skill's state-management examples are guidance
for that workflow, not a universal requirement for every Flutter application.
[^architecture-skill] [^architecture-docs]

[^architecture-skill]: flutter-apply-architecture-best-practices skill
[^architecture-docs]: Flutter common architecture concepts
