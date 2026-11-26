# Wayfinder Drift

SQLite storage for Wayfinder retrieval. Add `wayfinder_drift` to an app that
uses `wayfinder_embeddings` and register the generation driver as the first
write format:

```dart
import 'package:wayfinder_drift/wayfinder_drift.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

final store = WayfinderKnowledgeStore(
  dataDirectory: dataDirectory,
  encoder: encoder,
  formats: const [SqliteGenerationFormat()],
);
```

See [SqliteGenerationFormat](lib/src/sqlite_generation_format.dart) for the
generation driver and [DriftStore](lib/src/drift_store.dart) for mutable
`BaseStore` callers. `DriftStore.findSimilar` is an exact full scan of one
source and model, scored with sqlite-vec's cosine distance function, not a KNN
index. The CLI and MCP server use the generation driver.

## Saved indexes

The first explicit `index` after switching a current, verified plain-file
index to SQLite republishes it without inference. Search can read the old
generation until then. Older CLI releases require a rebuild with inference
when they encounter a SQLite generation.

The configuration key is shared across formats. Two stores with different
write formats on the same data directory republish each other's generation on
every `index`. Give each writer a separate data directory if both run regularly.

The native sqlite-vec v0.1.9 query accepts at most 4,096 rows per request.
Larger requests use an exact scan over the allowed rows.

## Native assets

The build hook verifies and stages the pinned sqlite-vec extension from
[the vendored release assets](third_party/sqlite_vec/README.md). The hook
supplies Linux x64, macOS arm64 and Windows x64 binaries. Use an asset-aware
Dart command such as `dart run` or `dart build cli` to build an application.
Linux x64 is tested in source CI. macOS arm64 and Windows x64 runtime loading
are unverified.

## Development

Run the suite from this package; it needs no embedding model:

```sh
dart test --concurrency=2
```

The OKF retrieval gate loads the model. Prepare it with
`dart run melos run wayfinder_embeddings:prepare` from the root, then run:

```sh
WAYFINDER_EMBEDDING_MODEL=../wayfinder_embeddings/models/embedding.gguf \
  dart run tool/evaluate_okf_retrieval.dart --stores=drift --no-timing \
  --split=development,held_out \
  --baseline=../wayfinder_embeddings/fixtures/benchmarks/okf_retrieval_baseline.json \
  --output=okf-drift.json
```
