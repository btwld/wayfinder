# Changelog

## 0.1.0

- Chunks Dart, TypeScript, Markdown, and text files into stable, addressable
  segments with line ranges and symbol metadata.
- Ranks chunks with exact BM25, dense Ollama vectors, and Reciprocal Rank
  Fusion, with optional reranking and parent/child expansion.
- Stores chunks and embeddings in `MemoryStore` or the optional 768-dimension
  `ObjectBoxStore`.
- Ships a 65-query qrels fixture, a checked-in BM25 metrics baseline, and a
  regression gate test over `fixtures/corpus`.
- Not published. No consumer package depends on it yet.
