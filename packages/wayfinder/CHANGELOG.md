# Changelog

## 0.0.1-dev.0

- Validates explicit local OKF bundles through the existing OKF Profile checks.
- Indexes and searches bundle passages using verified local embeddings and
  persistent ObjectBox storage, preserving original citations.
- Reuses compatible vectors and rejects stale or incompatible indexes.
- Serves validation, indexing, and search over MCP stdio.
- Keeps contextual Profile judgment explicitly unassessed by automated checks.

Indexing and search require separately prepared model weights and native
libraries. The Dart package does not include the complete native runtime bundle.
