# 0.1.0 (unreleased)

- Initial model-free, revision-bound browsing implementation.
- Add the plain, immutable `KnowledgeRetainedBundle` value returned by synchronous
  `KnowledgeProjectSnapshot.loadBundle`; keep the reader OKF-free and browser-closed.
  No Markdown classification/parsing or execution policy crosses this boundary.
- Expose canonical byte-manifest fingerprints and immutable external existence
  observations; hosts own validation, isolates and revision/context checks.
