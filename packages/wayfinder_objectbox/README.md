# wayfinder_objectbox

Persistent Dart storage for chunks and embeddings. Add `wayfinder_objectbox`
to your dependencies and import
`package:wayfinder_objectbox/wayfinder_objectbox.dart` for `ObjectBoxStore`.
Use the same database directory when upgrading from the embeddings package.
The [store API](lib/src/storage/objectbox_store.dart) documents the
384-dimensional vector limit, approximate HNSW search, and the exact fallback
when too few results survive filtering.

Install the matching [ObjectBox native library](https://docs.objectbox.io/getting-started)
for your Dart or Flutter app. For workspace development, the installer verifies
the archive against the pins in the [native asset manifest](tool/objectbox_assets/manifest.json).
Change the root override, installer and manifest together when updating the
workspace's paired runtime.

## Saved indexes

This package has no saved-index format for `WayfinderKnowledgeStore`. A format
must return the exact nearest rows and leave a generation unchanged when it
reads it, as the
[nearest-row contract](../wayfinder_embeddings/lib/src/store/generation_format.dart)
states. HNSW is approximate, so exact answers needed a scan of the eligible
rows in the tested workload. ObjectBox also changed its `lock.mdb` file during
a read-only open on Linux x64.

## Development

From the workspace root, prepare the library and the model for the native
persistence integration test. Then run the suite from this package so the
ObjectBox loader can resolve the installed library in `lib/`.

```sh
dart run melos run objectbox:install
dart run melos run wayfinder_embeddings:prepare
cd packages/wayfinder_objectbox
WAYFINDER_REQUIRE_NATIVE=1 dart test --concurrency=2
```

For entity changes, run `dart run melos run build` from the root and preserve
the IDs and UIDs in [the model](lib/objectbox-model.json). The persistence tests
open and write back to an [existing 0.2.0 database](test/fixtures/objectbox-0.2.0/README.md).

The comparison and benchmark commands run from this package directory in a
workspace checkout. For commands that load the model, prepare it as above and
set `WAYFINDER_EMBEDDING_MODEL=../wayfinder_embeddings/models/embedding.gguf`.

```sh
dart run tool/evaluate_okf_retrieval.dart --stores=objectbox --no-timing \
  --split=development,held_out \
  --baseline=../wayfinder_embeddings/fixtures/benchmarks/okf_retrieval_baseline.json \
  --output=okf-objectbox.json
dart run tool/compare_embeddings.dart --store=objectbox --queries=QUERIES
dart run tool/benchmark_stores.dart DENSE_ARTIFACT_DIR OUTPUT
dart run tool/benchmark_retrieval_scale.dart SIZE OUTPUT
```
