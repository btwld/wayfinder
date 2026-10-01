---
type: Guide
title: Flutter edge-to-edge migration
description: Scope and migration steps for the selected Android edge-to-edge change.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T17:39:20Z }
sources:
  - id: flutter-edge-to-edge
    resource: https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/release/breaking-changes/default-systemuimode-edge-to-edge.md
    title: Set default SystemUiMode to edge-to-edge
---

# Migration scope

Starting with Flutter 3.27, the default `flutter.targetSdkVersion` targets
Android 15 (API 35), which opts the app into edge-to-edge display. The locked
document identifies Flutter 3.27 as the stable release for this change. An app
explicitly targeting an older Android SDK has a different migration scope.

For a temporary Android 15 opt-out, update the activity themes in both
`res/values/styles.xml` and `res/values-night/styles.xml` with
`android:windowOptOutEdgeToEdgeEnforcement`. Android 16 removes the opt-out,
and the old mechanism can cause crashes. Consult the source migration guide
for version-specific resource handling, then check the app layout on the
Android versions it supports.

This concept preserves the source's Android-version scope. It does not turn the
change into a universal Flutter rule or claim that an app is migrated without an
app-specific check.[^flutter-edge-to-edge]

[^flutter-edge-to-edge]: [Set default SystemUiMode to edge-to-edge](https://github.com/flutter/website/blob/ab59c614e780e2d6d44f07ae4a96238028f581a5/sites/docs/src/content/release/breaking-changes/default-systemuimode-edge-to-edge.md)
