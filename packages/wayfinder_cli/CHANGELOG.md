# 0.0.1

Application moves from wayfinder to wayfinder_cli. The executable remains wayfinder, including MCP. Core validation comes from wayfinder; native installs no longer require okfp.

# Changelog

## 0.0.1-dev.1

- Use the `wayfinder_embeddings` package for retrieval.
- Preserve saved indexes across the library rename; write compatible schema markers.
- Support `WAYFINDER_EMBEDDING_MODEL` while retaining the legacy override.
- Align package setup, native builds and documentation with Wayfinder naming.

## 0.0.1-dev.0

- Validates explicit local OKF bundles through the existing OKF Profile checks.
- Indexes and searches bundle passages using verified local embeddings and
  persistent ObjectBox storage, preserving original citations.
- Reuses compatible vectors and rejects stale or incompatible indexes.
- Serves validation, indexing, and search over MCP stdio.
- Keeps contextual Profile judgment explicitly unassessed by automated checks.

Indexing and search require separately prepared model weights and native
libraries. The Dart package does not include the complete native runtime bundle.
