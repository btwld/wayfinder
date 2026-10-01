---
type: Guide
title: Dart unit tests
description: A repeatable package:test workflow for Dart unit tests.
status: draft
generated: { by: process:flutter-knowledge-pilot, at: 2026-09-30T17:39:20Z }
sources:
  - id: dart-unit-skill
    resource: https://github.com/dart-lang/skills/blob/0d9f1c4a0ae29d6f5180bf6143d7997ec3bacf49/skills/dart-add-unit-test/SKILL.md
    title: dart-add-unit-test skill
---

# Guidance

Place Dart unit tests under the package `test/` directory and use a `_test.dart`
suffix. Use `package:test`, grouping related cases and asserting behavior with
`expect`. Use `setUp` and `tearDown` for shared state, and `async`/`await` for
asynchronous cases. Use mocks only where a dependency boundary needs isolation.

Run a pure Dart package with `dart test`. A Flutter package uses its Flutter test
runner; integration tests need an explicit path because the default unit-test
command does not discover them.

The upstream skill is a procedure source. It does not prescribe one application
architecture or imply that every test needs a mock.[^dart-unit-skill]

[^dart-unit-skill]: [dart-add-unit-test skill](https://github.com/dart-lang/skills/blob/0d9f1c4a0ae29d6f5180bf6143d7997ec3bacf49/skills/dart-add-unit-test/SKILL.md)
