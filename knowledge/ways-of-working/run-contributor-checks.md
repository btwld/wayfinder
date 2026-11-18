---
type: Guide
title: Run the contributor checks
description: The core commands, the test lanes, formatting, and the two knowledge commands.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:32:44Z
sources:
  - id: contributing
    title: Contributing to Wayfinder
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/contributing.md#checks
---

# Checks

From the root, run the core checks used by [CI](../../.github/workflows/ci.yml):

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages/wayfinder/lib packages/wayfinder/test
dart analyze --fatal-infos
(cd packages/wayfinder && dart test --concurrency=2 --exclude-tags stress)
(cd packages/wayfinder && dart test --concurrency=2 --tags stress test/project/file_lock_test.dart)
dart run tool/generate_published_schemas.dart --check
python3 tool/ci/verify-configured-example.py
python3 tool/ci/verify-independent-profile.py
python3 tool/ci/verify-knowledge.py
python3 tool/ci/verify-links.py
```

The quick core lane excludes only `stress`. The explicit stress lane above keeps
all 50 rounds of the real concurrent native flock/errno regression; run it when
locks change. CI runs both lanes on minimum Dart and stable, with the original
stress repetition count and timeout. Plain `dart test` still includes stress.

Embeddings has a separate explicit `native` lane. From
`packages/wayfinder_embeddings`, use:

```sh
dart test --concurrency=2 --exclude-tags native
# After preparing the pinned model and installing ObjectBox:
WAYFINDER_REQUIRE_NATIVE=1 dart test --concurrency=2 --tags native
```

Model/library presence never enables native tests by itself. The requirement
flag enables native inference, real ObjectBox persistence/migration and
installed-library verification; missing prerequisites then fail instead of
skipping. Without the flag, plain `dart test` skips native-tagged cases even if
assets remain installed. Fake-engine/CountingEmbedder tests and pure ObjectBox
schema/scoring checks remain in the model-free lane. The stable native job
selects tagged coverage and retains all bundle/integration/retrieval gates;
minimum/stable keep the complete model-free suite.

`dart run melos run lint` checks all workspace packages. Package test runs are
serialized because workspace members share native build-hook output; concurrent
runs can race during library copying or macOS codesigning. Use concurrency 2 for
the commands above and coordinate heavy invocations with other agents on the
machine; separate test invocations do not share that limit. `verify-links.py`
checks every local link and anchor; compare changed wording with its
authoritative source yourself. Report what ran; validation checks conformance,
not the judgment a skill asks for.

`packages/wayfinder_flutter` is outside the workspace and needs Flutter. Its
[README](../../packages/wayfinder_flutter/README.md#development) lists its checks.

# Formatting and documentation

Use Dart 3.11.0 or later. **Format with stable**, which defines CI's canonical
style; the floor SDK can format differently and is used for analysis/tests only.
For docs/skills, check local links and authoritative wording. Release-tool changes
also run `tool/release/` checks. Example validation covers conformance; review
skill judgment separately. See [releasing](release-wayfinder.md) for publication/binaries.

# Hosted runner policy

The `test` matrix analyzes all packages and runs model-free tests plus the
full core lock stress on Dart 3.11.0 and stable. The stable-only
`native-retrieval` job selects native-tagged model/ObjectBox integration and
keeps retrieval quality, relocated bundles and installer verification. This avoids
running that complete native pipeline twice per commit; native execution on
the minimum SDK is no longer a CI promise. Stable Linux artifacts still belong
to the exact tested commit, and the three-platform distribution remains paused.

Portable knowledge contracts and native loader regression tests now run in the
core suite (`test/knowledge/` and `test/project/knowledge/`). From `tool/ci`, run
`python3.13 verify-reader-closure.py` after `dart pub get`: it follows the actual
transitive import/export/part closure of `package:wayfinder/knowledge.dart`,
including every conditional branch, and rejects native/OKF/Flutter imports.
The existing `wayfinder.dart` and `project.dart` remain native entries; package
runtime dependencies are not confused with a portable entry's import closure.
The separate Flutter workflow tests the memory/local reader and graph suite
when core/Flutter sources change; Flutter stays outside the root workspace.
See [reader integration](../../packages/wayfinder_flutter/doc/integration.md).
