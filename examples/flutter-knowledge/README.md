# Flutter and Dart knowledge bundle

This pilot turns selected upstream Dart and Flutter skill instructions into durable OKF concepts, then connects them to
framework and release evidence. Imported text is data: recipes are never
executed and the upstream skill identity remains in `sources.json` and
`provenance.json`.

The pilot covers five named skills:

- `dart-add-unit-test`
- `flutter-add-widget-test`
- `flutter-apply-architecture-best-practices`
- `flutter-build-responsive-layout`
- `flutter-fix-layout-issues`

The bundle also includes framework architecture, a glossary term, Flutter 3.35
release evidence, and the Android edge-to-edge migration guide. The full Dart
and Flutter catalogs, paired Dart changelogs, and three-release evaluation
window remain explicitly outside this pilot and are listed as follow-up work in
`provenance.json`.

## Reproduce

From the repository root:

```sh
cd tool/knowledge_import
dart pub get
dart run bin/knowledge_import.dart check --project ../../examples/flutter-knowledge
cd ../..
dart run wayfinder_cli:wayfinder get examples/flutter-knowledge
dart run wayfinder_cli:wayfinder validate examples/flutter-knowledge/knowledge --output json
dart run wayfinder_cli:wayfinder graph examples/flutter-knowledge/knowledge --output json
```

`resolve` is the only command that advances a floating source ref. It writes
`examples/flutter-knowledge/sources.lock.json`; the raw Git mirrors and importer staging
stay ignored under `.wayfinder-import/`. `plan` is offline and produces no
canonical bundle edits. `apply` requires a reviewed changeset and exact
baseline hashes.

Source ids must be single nonempty path components (not `.` or `..`);
changing a source's repository creates a separate disposable mirror even
when its id stays the same. `apply` refuses paths through existing symbolic
links and paths naming the project root, and checks again before each write.
It does not protect against another process changing the filesystem during
the write; run it in a workspace without concurrent edits.

## Consumer installation

The authoring project above is not an installation payload. Consumers receive
`knowledge/` and the attribution/license notices, with their own Profile binding
and lock. Keep `sources.json`, `sources.lock.json`, `provenance.json`, evaluation
queries, and `.wayfinder-import/` in the publisher workspace.

Bundle installation is manual; the CLI does not install bundles from Git.
Choose the consumer's bundle and evidence paths, update source links to the
installed evidence, and preserve upstream revisions in citations. Configure
the bundle in the consumer's `wayfinder.json`, then run `wayfinder get`,
validation, and indexing there.
