# Frozen plain-file generation

Produced by the actual `WayfinderKnowledgeStore` at pre-migration commit
`0fae2b78619f1d4406e232ec1e207060f2476f86`, using the unchanged synthetic
`store-bundle` fixture and `TestEncoderProvider` (`fixture-v1`).

`snapshot.json`, `vectors.f32`, and `search.json` are old-writer outputs, not
exports from the SQLite implementation. Only the temporary absolute bundle
root is replaced with `@BUNDLE_ROOT@`; the public search result omits elapsed
milliseconds. Tests substitute their root when installing this generation.
The binary vectors and their SHA-256 remain exactly as the old writer emitted.
Do not regenerate these files with the current writer.
