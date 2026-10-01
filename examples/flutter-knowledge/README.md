# Flutter and Dart knowledge bundle

This is the first, source-attributed pilot produced from the plan in
`docs/plans/flutter-knowledge-bundle/`. It turns selected upstream Dart and
Flutter skill instructions into durable OKF concepts, then connects them to
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

Native indexing, semantic search, and MCP require the installed Wayfinder model
and native runtime. They were not treated as successful gates for this source
bundle unless a run is recorded separately.
