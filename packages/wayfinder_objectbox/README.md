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

The shipped API is a `BaseStore` for chunks and embeddings. The saved-index
experiment used a 50-candidate HNSW pool without a filter, a 100-candidate pool
with half the rows allowed, and exact scoring by row ID with 5% allowed. The
narrow-filter route uses ID reads when the requested pool exceeds half the
index or HNSW yields too few eligible rows. HNSW is approximate. The
[nearest-row contract](../wayfinder_embeddings/lib/src/store/generation_format.dart)
requires exact results and a read-only generation. ObjectBox changed its lock
file even after the read-only store closed on Linux x64, and exactness would
require scanning eligible rows whenever the candidate pool lacked a guarantee.

The knowledge store's configuration key excludes the write format. Two
`WayfinderKnowledgeStore` instances with different write formats on one data
directory republish each other's index on every index run.

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
dart run tool/compare_embeddings.dart --store=objectbox --queries=QUERIES
dart run tool/benchmark_stores.dart DENSE_ARTIFACT_DIR OUTPUT
dart run tool/benchmark_retrieval_scale.dart SIZE OUTPUT
```
