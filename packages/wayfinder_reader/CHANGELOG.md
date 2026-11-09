# 0.1.0 (unreleased)

- Initial model-free, revision-bound browsing implementation.
- Add the plain, immutable `KnowledgeRetainedBundle` value returned by synchronous
  `KnowledgeProjectSnapshot.loadBundle`; keep the reader OKF-free and browser-closed.
  No Markdown classification/parsing or execution policy crosses this boundary.
- Keep canonical byte-manifest fingerprints on captures and the pure
  `knowledgeManifestFingerprint` function; expose immutable external existence
  observations. Hosts own validation, isolates and revision/context checks.
