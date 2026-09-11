# ObjectBox configuration and native build review

Reviewed 2026-09-10 for the Wayfinder package migration. This document records
the configuration we ship, its verification and the limits of platform support.

## Dependencies and schema

Wayfinder is a Dart Native CLI, so it uses `objectbox` plus the separately
downloaded C runtime. It does not need the Flutter-only
`objectbox_flutter_libs` plugin. This follows the
[Dart Native setup instructions](https://docs.objectbox.io/getting-started#dart-native).

The Dart runtime and generator are both pinned to **5.0.4**. The native library
is **5.3.2**. Their version numbers need not be identical: the installed 5.0.4
binding requires C API 5.0.0 or later and database core
`5.0.0-2025-09-27` or later. The pinned 5.3.2 runtime meets those checks, and our
native tests exercise it. Keep this tested combination during the naming change;
review runtime/generator updates together with the upstream changelog instead of
automatically floating native versions. Sources:
[5.0.4 binding](https://github.com/objectbox/objectbox-dart/blob/v5.0.4/objectbox/lib/src/native/bindings/bindings.dart),
[5.3.2 native release](https://github.com/objectbox/objectbox-c/releases/tag/v5.3.2).

Commit both `objectbox-model.json` and `objectbox.g.dart`. Preserve entity and
property UIDs; regenerate with `melos build` only when the entity model changes.
The package rename changes Dart import URIs, not database identity. ObjectBox's
[model identity documentation](https://docs.objectbox.io/advanced/meta-model-ids-and-uids)
explains why deleting or recreating the model metadata can break existing stores.

The application opens an explicit per-user, per-bundle store and closes it after
each operation. Staged generations and the existing process lock protect index
updates. The `384-v1` marker is our vector-schema compatibility guard, separate
from ObjectBox's model metadata. Both the new `wayfinder_embeddings.schema` and
legacy `knowledge_embeddings.schema` are recognized; conflicting markers refuse
opening. The rename preserves vectors, chunk IDs and model/configuration hashes.

## Native assets and packaging

`packages/wayfinder_embeddings/tool/install_objectbox.sh` selects OS and CPU,
downloads the pinned release and verifies its archive SHA-256 before extraction.
It refuses unknown platforms. The build provenance manifest records archive
and extracted-library hashes for all eight upstream assets; each was downloaded
and hashed during this review.

Both native builders now recheck the installed library against the trusted
platform hash before compilation and recheck the copied bundle library. This
closes the gap where an accidentally replaced local library could have been
redistributed after the installer had originally verified a different file.
The builders include ObjectBox's Apache-2.0 license, attribution and hash manifest
under `licenses/objectbox/`. The native repository identifies its license in its
[release README](https://github.com/objectbox/objectbox-c/tree/v5.3.2#license).
Application/library BSD licenses and model notices remain separate.

The bundle carries the executable, Dart/llamadart native assets, ObjectBox
(`lib/` on Linux/macOS, `bin/` on Windows), the verified model and its manifest.
Dart emits native code assets under `lib/` on Windows too. The pinned
llamadart 0.8.23 backend loader searches beside the executable there, so both
builders additionally stage those DLLs in `bin/`, retaining `lib/` for Dart's
compiled asset mappings. Windows CI caught this distinction: source execution
loaded its CPU backend, while the first relocated AOT bundle could not find it.
Copy the whole bundle when relocating it. Validation does not use a database or
embedding model; indexing and search need the complete native assets.

## Verification and remaining platform limits

The schema migration tests cover legacy-only and new-only markers, reopening
without losing chunks, conflicting markers and refusal without modifying a
database. Build tests compare installer pins with the manifest, verify staging
and notices, and reject altered native bytes. Native CLI/MCP probes run from a
relocated bundle, away from the source package and its working directory.

Archive availability and checksum verification do not establish execution
support on a platform. CI exercises native retrieval on Linux x64 and macOS;
Windows and other CPU targets require real native build/relocation/search tests
before their complete Wayfinder bundles can be advertised. Upstream ObjectBox
support alone is insufficient: llamadart and Dart AOT must also work there.

The generic ObjectBox store uses HNSW. The OKF adapter performs exact scoring
over eligible stored vectors in Dart. Renaming/configuring ObjectBox does not
make that path approximate or establish large-corpus performance; retain the
separate retrieval benchmark limits documented in the
[retrieval guide](wayfinder_embeddings.md).
