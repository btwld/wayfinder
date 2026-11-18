---
type: Guide
title: Develop in the Dart workspace
description: Workspace layout, ObjectBox installation, the pinned model and native bundle builds.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:32:44Z
sources:
  - id: contributing
    title: Contributing to Wayfinder
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/contributing.md#dart-workspace-development
---

# Dart workspace development

`wayfinder_embeddings` keeps its tests, fixtures, and BSD license in the
package directory. See its [README](../../packages/wayfinder_embeddings/README.md)
for the implementation and evaluation commands. Its optional native
`ObjectBoxStore` backend, which the knowledge store and the `wayfinder` command
do not use, needs `dart run melos run objectbox:install`; regenerate its committed ObjectBox
files with `dart run melos run build` only when entity schemas change. The root
`pubspec.yaml` overrides Dart `objectbox` to the version the installer pins
natively; change the override, the installer and
`tool/objectbox_assets/manifest.json` together.
`wayfinder_embeddings` keeps `analyzer` out of its runtime dependencies;
`python3 tool/ci/verify-embeddings-closure.py` checks that rule in CI.
The committed baseline chunks are the source of truth for the judged retrieval
corpus. Its tools and tests replay the Dart chunks and compare against that
baseline without rewriting it; see its [fixtures README](../../packages/wayfinder_embeddings/fixtures/README.md).

For native semantic retrieval, `dart run melos run wayfinder_embeddings:prepare` stages the pinned
25.28 MB model. `dart run melos run wayfinder_embeddings:build` creates a
CLI bundle containing the model and native libraries. The model choice is
recorded in [Embed with a verified local model](../retrieval/embed-with-a-local-model.md). `wayfinder validate` provides
bundle validation; search examples and evaluation commands live in the
[embedding package](../../packages/wayfinder_embeddings/README.md#command-line-entry-points).
