---
type: Architecture Decision Record
title: Keep the Flutter reader outside the Dart workspace
description: Reader models and widgets live in `packages/wayfinder_flutter`, free of any design kit and out of the pub workspace.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: decision-flutter-reader
    title: Flutter reader SDK outside the Dart workspace
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#flutter-reader-sdk-outside-the-dart-workspace
---

# Decision

Keep Flutter reader models and widgets in `packages/wayfinder_flutter`, free of any design kit, so desktop and phone readers share one implementation while hosts keep sign-in, storage, navigation and chrome.
The package stays out of the pub workspace and root analysis so that CLI and library contributors need no Flutter SDK; the cost is a separate workflow and dependency resolution for it.
