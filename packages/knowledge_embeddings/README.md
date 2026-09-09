# Knowledge Embeddings

Chunk, embed, and search code and documents from Dart. The package runs
locally: exact BM25 over chunk text, dense vectors from an Ollama runtime, and
Reciprocal Rank Fusion (RRF) over the two.

## What it does

- **Chunk** Dart, TypeScript, Markdown, and text files into addressable
  segments with line ranges and symbol metadata. Chunk ids are stable hashes of
  the source path, line range, type, and content.
- **Rank** chunks for a natural-language query with lexical, dense, or hybrid
  retrieval, with optional cross-encoder reranking.
- **Expand** a precise hit to its enclosing class, namespace, or file.

Chunk budgets count non-whitespace characters, so indentation and blank lines
do not force a split.

## Ingest and search

```dart
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';

Future<void> main() async {
  // 1. Register a chunker per content type.
  final registry = ChunkerRegistry()
    ..registerChunker(DartChunker())
    ..registerChunker(MarkdownChunker());

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .toList();

  // 2. Ingest the files. chunkFiles runs the chunkers; ingest embeds and
  //    stores the result. Call chunkFiles first when you also need the chunks.
  final embedder = OllamaEmbedder();
  final store = MemoryStore();
  final pipeline = IngestionPipeline(
    chunkerRegistry: registry,
    embedder: embedder,
    store: store,
  );
  final chunked = chunkFiles(registry, files).toList();
  await pipeline.ingest(chunked);

  // 3. Fuse exact BM25 with the dense vectors.
  final chunks = await store.getAllChunks();
  final searcher = HybridContentSearcher(
    lexicalIndex: BM25LexicalIndex.fromChunks(chunks),
    semanticSearcher: ContentSearcher(store: store, embedder: embedder),
  );

  // 4. Search.
  final results = await searcher.search('refresh auth token', limit: 10);
  for (final result in results) {
    print('${result.similarity.toStringAsFixed(3)} '
        '${result.chunk.sourcePath}:${result.chunk.lineStart}');
  }

  await embedder.dispose();
  await store.close();
}
```

`SearchOptions` filters candidates before ranking by file pattern, language, or
chunk metadata.

## Composing searchers

`ContentSearcher`, `HybridContentSearcher`, and `RerankingContentSearcher` all
implement `Searcher`, so they compose without adapters.

```dart
// Cross-encoder precision stage over any first-pass searcher.
final reranked = RerankingContentSearcher(
  searcher: hybridSearcher,
  reranker: TeiReranker(baseUrl: Uri.parse('http://127.0.0.1:8080')),
  candidateLimit: 50,
);

// Small-to-large: match precise child chunks, present the enclosing context.
final contextual = ParentChildSearcher(
  searcher: hybridSearcher,
  resolver: ParentChildResolver(chunks: chunks),
);
final contextualResults = await contextual.search('refresh auth token');
for (final result in contextualResults) {
  print('matched ${result.child.chunk.type} in ${result.contextChunk.type}');
}
```

`TeiReranker` calls the `/rerank` endpoint of Hugging Face Text Embeddings
Inference. Reranking stays opt-in because it needs a separate local model and
the recorded qrels evidence does not justify a default.

`ParentChildResolver` prefers symbol metadata such as `class`, `mixin`,
`extension`, or `enum`, then falls back to the smallest enclosing source range.
It collapses repeated contexts to the first child hit.

## Stores

- `MemoryStore` is the default. It performs exact brute-force vector search and
  accepts any embedding dimension. Use it for tests, evaluation, and
  single-repository search.
- `ObjectBoxStore` persists chunks and embeddings and searches with an HNSW
  index. Its generated entity is fixed at 768 dimensions. It needs a platform
  library that is not committed; install it with `melos run objectbox:install`.
  `test/objectbox_store_test.dart` skips itself when the library is absent.

Both implement `BaseStore`. `storeBatch` writes chunks and embeddings together;
`ObjectBoxStore` overrides it with one transaction.

## Ollama setup

`OllamaEmbedder` wraps the official
[`ollama_dart`](https://pub.dev/packages/ollama_dart) client. It checks that the
model is installed and throws `OllamaEmbedderException` with the `ollama pull`
command when it is not. Chunks are embedded through one batched `/api/embed`
request per file.

```bash
ollama serve
ollama pull embeddinggemma        # package default, native 768-dim
ollama pull qwen3-embedding:0.6b  # code-tuned, native 1024-dim
```

```dart
final embedder = OllamaEmbedder();

// qwen3-embedding:0.6b is native 1024-dim. Ask the server for 768 so the
// vectors also fit ObjectBoxStore; MemoryStore accepts any dimension.
final codeEmbedder = OllamaEmbedder(
  model: OllamaModel.recommendedCodeEmbedding,
  dimensions: 768,
);

// Descriptor form, for example from a command line.
final compact = OllamaEmbedder.fromModelName('embeddinggemma@512');
```

`dimensions` is forwarded to the Ollama runtime, which performs the reduction.
The effective `modelName` carries an `@dimensions` suffix whenever the output
dimension differs from the model's native one, so vectors from two dimensions
never collide in one store.

## Custom chunkers and embedders

Extend `BaseChunker` or `BaseEmbedder`. Register a chunker with
`ChunkerRegistry` so files route to it by content type or extension. Override
`BaseEmbedder.generateEmbeddings` when the backend accepts a batch.

## Evaluation

The retrieval benchmark, the qrels fixture, and the BM25 regression gate live
in `tool/`. See [the evaluation runbook](../../docs/knowledge_embeddings_eval.md)
for the commands, the current metrics, and the recorded negative results.

## License

BSD 3-Clause. See the LICENSE file.
