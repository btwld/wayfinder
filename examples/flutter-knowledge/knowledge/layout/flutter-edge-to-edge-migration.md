---
type: Guide
title: Flutter edge-to-edge migration
description: Scope and migration steps for the selected Android edge-to-edge change.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T01:20:47Z }
sources:
  - id: flutter-edge-to-edge
    resource: https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/release/breaking-changes/default-systemuimode-edge-to-edge.md
    title: Set default SystemUiMode to edge-to-edge
---

# Migration scope

The selected breaking-change document says that Android 15 and later use
edge-to-edge display behavior by default, and that Android 16 removes the prior
opt-out path. It points to version-specific resources and migration guidance for
apps that need to avoid crashes or layout assumptions on Android 16 and later.

This concept preserves the source's Android-version scope. It does not turn the
change into a universal Flutter rule or claim that an app is migrated without an
app-specific check.[^edge]

[^edge]: Set default of `SystemUiMode` to edge-to-edge
