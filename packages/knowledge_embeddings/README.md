# Knowledge Embeddings

Chunk, embed, and search code and documents from Dart. The package runs
locally: exact BM25 over chunk text, dense vectors from an in-process llamadart model, and
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

Budgets guide splitting and summarization; an indivisible line, sentence,
signature, code block, or table may exceed the configured budget. Dart uses
the analyzer AST. TypeScript uses a structural scanner rather than a complete
TypeScript/TSX parser, so unfamiliar syntax can fall back to a file chunk.

Markdown emits `heading`, `paragraph`, `code`, `table`, and `footnote` chunks. A
run of footnote definitions and their indented continuations becomes one
`footnote` chunk: it is reference apparatus, and a one-line definition otherwise
competes with body passages. Filter it with `SearchOptions.chunkTypes`.

## Search an OKF bundle

Import `package:knowledge_embeddings/okf_knowledge.dart` for the separate
`KnowledgeSnapshot`, `KnowledgeIndex`, and `KnowledgeSearchPolicy` adapter.
It uses upstream OKF metadata and links, preserves source citation lines, and
atomically synchronizes changed/deleted concepts. Footnote definitions are not
retrievable passages there: OKF resolves per-claim attribution through `sources`
(OKF 0.2 §5.1). A concept whose body is only headings and footnotes keeps them,
so nothing becomes unsearchable. Metadata-only changes reuse
vectors when they do not change embedding inputs; contextual titles/headings
are embedding inputs. A stable caller-supplied bundle ID isolates ownership in a shared store.

Run `dart run example/knowledge_example.dart` for contextual BM25 with no model,
or append `--dense` after preparing the local model. The example explicitly
selects current guidance, a query date, governing sources, and one-hop links.
These are consumer choices, not new OKF rules. History queries can select
historical status instead. Draft and unverified concepts remain eligible.

The adapter defaults to BM25 and no implicit policy; enable `includeContext`
for title/heading inputs and supply `countTokens`/`maxTokens` with an encoder.
Dense retrieval scores the entire eligible vector set exactly; ObjectBox adds
persistence, not a relevance advantage. The caller owns the store and encoder.
Coordinate writes when multiple index instances share a bundle. Search responses
separate query-ranked `matches` from bounded policy-selected `context`, including
inclusion reasons and unresolved/excluded-context notices. They are candidates,
not an answerability verdict.

ObjectBox persists passage text and vectors. `KnowledgeSnapshot.toMap/fromMap`
round-trips fitted passages and the source inputs needed to reconstruct the OKF
graph. `KnowledgeIndex.openSnapshot` opens a committed snapshot without document
encoding or token fitting; the caller must provide its matching store and
embedding configuration. Query-vector caching lasts only for that instance.
[Station](../station/README.md) owns atomic snapshot/database publication and
freshness checks for its local CLI.

See [the component experiment](../../docs/knowledge_embeddings_ablation.md) for
measured improvements and regressions with and without embeddings.

The [model-free versus local embedding benchmark](../../docs/knowledge_embeddings_comparison.md)
adds a frozen topic-separated test set and isolated runtime, build, update, and
storage-scale measurements. Its keyword control stays in evaluation tooling.
The [small-model comparison](../../docs/knowledge_embeddings_model_comparison.md)
tests Arctic XS, Arctic S and BGE-small, including Q8/Q4 variants, using the same
frozen passages and judgments. Alternative weights stay in benchmark tooling;
the application model remains Arctic XS Q8_0.

## Command-line entry points

From the repository root, the profile CLI validates a bundle:

```bash
dart run okf_profile:okfp validate examples/knowledge
```

`okfp --help` currently lists only `validate`; it has no embedding or search
subcommand. [Station](../station/README.md) adds top-level `validate`, `index`
and `search` commands using local embeddings. The following developer commands run from this package directory
(`packages/knowledge_embeddings`):

```bash
# Download/cache and verify the pinned XS model once.
dart run tool/prepare_model.dart

# Run the fixed-query OKF fixture example with local embeddings.
dart run example/knowledge_example.dart --dense

# Compare retrieval components on the committed OKF fixture.
dart run tool/evaluate_okf_retrieval.dart --native --stores=memory --split=development --output=comparison_results/okf-development.json

# Build the generic corpus evaluation CLI with its native assets.
# ObjectBox must already be installed: run melos run objectbox:install at root.
dart run tool/build_embeddings.dart --offline
```

Run `dart run example/knowledge_example.dart` without `--dense` for BM25 and
no model loading. The example's bundle and query are fixed in its source.
`compare_embeddings` accepts a corpus directory and query/judgment files for
evaluation; it is not an interactive OKF bundle search interface. Use the
`KnowledgeSnapshot`/`KnowledgeIndex` API for a consumer's own bundle and query.

The [accepted decision](../../docs/adr/0009-local-knowledge-retrieval.md) keeps
XS as the local model and records the next passage-selection experiments.

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
  final embedder = await LlamaEmbedder.open();
  final store = MemoryStore();
  try {
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
  } finally {
    await embedder.dispose();
    await store.close();
  }
}
```

`SearchOptions` selects file paths, glob patterns, chunk types, and metadata.
BM25 filters before scoring. Dense search filters ranked candidates and doubles
its fetch window up to 32 times the requested limit; selective filters can
therefore return fewer results even when more matches exist deeper in the store.

Ingestion deduplicates chunk ids across both stored data and the current call.
An existing chunk still receives a missing embedding for the active source/model.
Metadata-only updates are persisted without regenerating vectors. Rebuild any
existing BM25 index to see the updated snapshot. Changed text needs a new chunk
ID; ingestion does not remove obsolete chunks automatically. Delete those
chunks explicitly or rebuild a fresh store when synchronizing changed files.

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
  index. Its generated entity is fixed at 384 dimensions. It needs a platform
  library that is not committed; install it with `melos run objectbox:install`.
  The installer pins native 5.3.2, tested with Dart package 5.0.4, verifies the
  release archive's SHA-256 before extracting it, and writes only to this
  package's `lib/` directory.
  `test/objectbox_store_test.dart` skips itself when the library is absent.
  `minimumSearchCandidates` defaults to 50 independently of the result limit,
  trading extra work for the recall measured on the fixture corpus.

Both implement `BaseStore`. `storeBatch` writes chunks and embeddings together;
`ObjectBoxStore` overrides it with one transaction.
Memory search uses cosine similarity, returns zero for zero vectors, and scales
finite vectors before scoring to avoid numeric overflow or underflow.

## Local examples and fixtures

Run these from the package directory:

```bash
dart run example/basic_example.dart
dart run example/code_example.dart
```

Both read the checked-in `fixtures/samples/` files. The sample corpus covers
all four chunkers, including plain text and Markdown table examples inside code
fences. Markdown code blocks retain literal table syntax; actual tables inherit
their heading metadata and are omitted when `includeTables` is false.

The sample corpus has its own golden snapshot. The separate `fixtures/corpus/`
retrieval benchmark retains its recorded queries and metrics.

## Local model and builds

The package pins `llamadart` 0.8.23 and Arctic Embed XS Q8_0: a 25,279,840-byte
GGUF producing 384-dimensional vectors. Development and CLI builds need Dart
3.10.7+, the minimum required by the pinned llamadart release. Build hooks and
`dart build cli` were introduced in Dart 3.10; the tested Dart 3.11 CLI still
labels its bundle command as preview.

From the repository root:

```bash
melos run embeddings:prepare
melos run objectbox:install
melos run embeddings:build
```

The prepare step uses llamadart's shared download cache, an immutable revision,
and SHA-256 verification. It stages `models/embedding.gguf` and a manifest;
weights stay out of Git. `objectbox:install` verifies its pinned release archive
the same way, so every native asset a bundle ships is checked against a recorded
hash. From this package, add `--offline` to
`dart run tool/prepare_model.dart` or `dart run tool/build_embeddings.dart` to
require an already staged or cached model. Native build hooks may still need
their own runtime cache; `--offline` controls model acquisition only.

Hook settings live once in the workspace `pubspec.yaml`. When consuming this
package from another app or workspace, configure its root pubspec explicitly:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp]
      llamadart_native_backends: [cpu]
```

Dart reads these settings from the consuming root, not from dependencies.
The native libraries use llamadart's hook; GGUF weights use the explicit
preparation/packaging step because Dart's `data_assets` support is experimental.

The build creates `build/embeddings/bundle/` with an executable under `bin/`,
native libraries under `lib/` (ObjectBox's DLL is beside the executable on
Windows), and weights, manifest, license, and attribution under `models/`.
Distribute the whole bundle. Runtime model lookup uses the executable location,
then the development `models/` directory; `KNOWLEDGE_EMBEDDING_MODEL` or the
CLI's `--model` can override it. Runtime inference never downloads weights.

`LlamaEmbedder.open()` verifies the file before loading. It owns the engine;
call `dispose()` in a `finally` block. A backend that never reports itself
started is retried once on a fresh engine, because the first load from a
freshly installed bundle can exceed the runtime's fixed worker startup timeout
while the operating system validates the native libraries. Documents use their
original text; queries receive the model's retrieval prefix. Both produce
normalized vectors. The cache identity includes the artifact bytes,
preprocessing contract, and long-input policy, so changed settings cannot
silently reuse incompatible vectors. Download URL and license are provenance,
not identity: another mirror of the same verified bytes reuses stored vectors.

The tokenizer allows **512 tokens including special tokens and the query
prefix**. Chunk character budgets do not guarantee that limit. The default
rejects oversized inputs. Explicit `LongInputPolicy.truncate` (CLI
`--long-input=truncate`) encodes a prefix and reports `truncatedInputs`; stored
chunk text and source ranges remain complete. Prefer splitting oversized source
chunks when preserving full semantic coverage matters.

Existing databases using the previous vector schema require reindexing into a
**new directory**. The store refuses to open incompatible databases before
ObjectBox modifies them. Regenerate committed entity bindings with `melos build`
when changing the schema; preserve `lib/objectbox-model.json` UID history.

Run `dart run example/native_example.dart` after preparing the model. The
[implementation report](../../docs/knowledge_embeddings_local_search.md) explains
model selection, build tradeoffs, and measured retrieval behavior.
The [knowledge retrieval review](../../docs/knowledge_embeddings_knowledge_retrieval.md)
covers authority, lifecycle, ObjectBox filtering, and new tests with and without
embeddings. Generic Markdown chunking preserves caller-supplied metadata; an
OKF adapter still needs to parse and supply the concept metadata.

## Custom chunkers and embedders

Extend `BaseChunker` or `BaseEmbedder`. Register a chunker with
`ChunkerRegistry` so files route to it by content type or extension. Override
`BaseEmbedder.generateEmbeddings` when the backend accepts a batch.

## Evaluation

The [documentation guide](../../docs/knowledge_embeddings.md) maps each
experiment to its question and limitations. The retrieval benchmark, the qrels
fixture, and the BM25 regression gate live in `tool/`.
See [the evaluation runbook](../../docs/knowledge_embeddings_eval.md)
for commands, metrics, and the regression gate.

## License

Dart package: BSD 3-Clause. See `LICENSE`. The bundled model uses Apache-2.0;
its license and conversion attribution are in `tool/model_assets/`.
