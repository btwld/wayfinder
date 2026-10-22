# Wayfinder Embeddings

Chunk, embed, and search code and documents from Dart. The package runs
locally with dense vectors from an in-process llamadart model.

## What it does

- **Chunk** TypeScript, Markdown, and text files into addressable segments
  with line ranges and symbol metadata. Chunk ids are stable hashes of the
  source path, line range, type, and content. Dart chunking lives in
  [`wayfinder_dart_chunker`](../wayfinder_dart_chunker/README.md), so this
  package does not depend on the analyzer.
- **Rank** chunks for a natural-language query with dense
  retrieval and optional cross-encoder reranking.
- **Expand** a precise hit to its enclosing class, namespace, or file.

Chunk budgets count non-whitespace characters, so indentation and blank lines
do not force a split.

Budgets guide splitting and summarization; an indivisible line, sentence,
signature, code block, or table may exceed the configured budget. TypeScript
uses a structural scanner rather than a complete TypeScript/TSX parser, so
unfamiliar syntax can fall back to a file chunk.

Markdown emits `heading`, `paragraph`, `code`, `table`, and `footnote` chunks. A
run of footnote definitions and their indented continuations becomes one
`footnote` chunk: it is reference apparatus, and a one-line definition otherwise
competes with body passages. Filter it with `SearchOptions.chunkTypes`.

## Search an OKF bundle

Import `package:wayfinder_embeddings/okf_knowledge.dart` for the separate
`KnowledgeSnapshot`, `KnowledgeIndex`, and `KnowledgeSearchPolicy` adapter.
It uses upstream OKF metadata and links, preserves source citation lines, and
atomically synchronizes changed/deleted concepts. Footnote definitions are not
retrievable passages there: OKF resolves per-claim attribution through `sources`
(OKF 0.2 §5.1). A concept whose body is only headings and footnotes keeps them,
so nothing becomes unsearchable. Metadata-only changes reuse
vectors when they do not change embedding inputs; contextual titles, short descriptions, and heading paths
are embedding inputs. A stable caller-supplied bundle ID isolates ownership in a shared store.

Run `dart run example/knowledge_example.dart` after preparing the local model. The example explicitly
selects current guidance, a query date, governing sources, and one-hop links.
These are consumer choices, not new OKF rules. History queries can select
historical status instead. Draft and unverified concepts remain eligible.

The adapter requires `embedder:` and applies no implicit knowledge policy.
Enable `includeContext` for title/heading inputs and supply
`countTokens`/`maxTokens` from the encoder.
Dense retrieval scores the entire eligible vector set exactly; ObjectBox adds
persistence, not a relevance advantage. Search fails if an eligible passage
lacks a compatible vector. The caller owns the store and encoder.
Coordinate writes when multiple index instances share a bundle. Search responses
separate query-ranked `matches` from bounded policy-selected `context`, including
inclusion reasons and unresolved/excluded-context notices. They are candidates,
not an answerability verdict.

ObjectBox persists passage text and vectors. `KnowledgeSnapshot.toMap/fromMap`
round-trips fitted passages and the source inputs needed to reconstruct the OKF
graph. `KnowledgeIndex.fromSnapshot` opens a committed snapshot without document
encoding or token fitting; the caller must provide its matching store and
embedding configuration. Query-vector caching lasts only for that instance.
[Wayfinder CLI](../wayfinder_cli/README.md) owns atomic snapshot/database publication and
freshness checks for its local CLI.

### Markdown retrieval context

Contextual inputs use labeled document title, optional description, full heading
path, structural context, and the original passage, in that order. Descriptions
must be nonempty strings of at most 240 Unicode scalars; longer descriptions stay
in metadata and are omitted from the derived input. Tags, type, status, sources,
and provenance remain metadata. No heading level or block type receives a fixed
ranking boost.

Tables retain their header and delimiter as context on every fitted fragment.
Fenced code retains its language identifier. Fitting prefers newline boundaries
for tables and code, then falls back to whitespace or lossless character splits
when an individual row or line is too large. Body text and citation offsets are
preserved; context never becomes source content. If context cannot fit the model
budget, the existing diagnosed body-only recovery still applies.

This input format uses `okf-context-v2`; body-only inputs retain `okf-body-v1`.
The CLI detects previous contextual indexes as stale. Run `wayfinder index` once
to rebuild; subsequent indexing reuses unchanged vectors.

### Oversized embedding inputs

`KnowledgeSnapshot.fitInputs()` measures each complete input with the supplied
model tokenizer, including context separators and special tokens. It prefers
whitespace boundaries, then subdivides oversized separators/identifiers at
Unicode code-point boundaries. Concatenating an original passage's fitted
fragments reconstructs that **pre-fit passage** exactly, with no overlap or
truncation. Leading and trailing whitespace stay attached to nonblank text,
and each complete fragment is checked against the token budget again; padding
never becomes a standalone blank embedding input.
This is not whole-document reconstruction: Markdown passage
selection and parsing still apply. The original `sources` map and source files
remain unchanged, including their line endings.

If an irreducible nonblank fragment cannot fit with its derived title/heading
prefix, the fitter discards that original chunk's provisional fragments and retries its
body without the prefix. Other chunks keep context. Original metadata remains
intact; the effective input, omission, original-chunk identity, UTF-16 offsets
(exclusive ends), and citations survive snapshot round trips and further fitting.
An irreducible body-only input, invalid budget, tokenizer error, or inference
failure still fails; strict encoder rejection is unchanged.

The snapshot's immutable `diagnostics` list contains `KnowledgeInputDiagnostic`
values with `code`, `sourcePath`, `lineStart`, `lineEnd`, and `affectedChunks`:

- `oversized_segment_split`: recovery required a non-whitespace split.
- `embedding_context_omitted`: recovery omitted the derived context prefix.

Diagnostics aggregate by path/code, enclose affected original-chunk line ranges,
count each original chunk once per code, and sort by path then code. Ordinary
whitespace splitting is silent. Additive private recovery attribution in snapshot
version 1 preserves deduplication after reopening and tighter fitting; older
snapshots without it have empty diagnostics. Call `fitInputs()` explicitly before
`synchronize()` when you need to inspect the fitted snapshot and diagnostics.
New boundaries or omitted context can change retrieval results; ranking algorithms
and model identity are unchanged.

Benchmark inputs and recorded results live in [`fixtures/`](fixtures/README.md).
Alternative model weights stay in benchmark tooling; the application model
remains Arctic XS Q8_0.

## Command-line entry points

From the repository root, the profile CLI resolves the example project's
Profile source and validates its bundle:

```bash
dart run wayfinder_cli:wayfinder get examples/bitwild
dart run wayfinder_cli:wayfinder validate examples/bitwild/knowledge
```

The [Wayfinder CLI](../wayfinder_cli/README.md) adds `index` and `search`
commands using local embeddings. The following developer commands run from this package directory
(`packages/wayfinder_embeddings`):

```bash
# Download/cache and verify the pinned XS model once.
dart run tool/prepare_model.dart

# Run the fixed-query OKF fixture example with local embeddings.
dart run example/knowledge_example.dart

# Compare retrieval components on the committed OKF fixture.
dart run tool/evaluate_okf_retrieval.dart --stores=memory --split=development --output=comparison_results/okf-development.json

# Build the generic corpus evaluation CLI with its native assets.
# ObjectBox must already be installed: run melos run objectbox:install at root.
dart run tool/build_wayfinder_embeddings.dart --offline
```

The knowledge example always loads the prepared model. Its bundle and query
are fixed in its source. The basic example is a model-free preview.
`compare_embeddings` accepts a corpus directory and query/judgment files for
evaluation; it is not an interactive OKF bundle search interface. Use the
`KnowledgeSnapshot`/`KnowledgeIndex` API for a consumer's own bundle and query.

The [accepted decision](../../docs/adr/0009-local-knowledge-retrieval.md) keeps
XS as the local model.

## Ingest and search

```dart
import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

Future<void> main() async {
  // 1. Register a chunker per content type. For Dart sources, add
  //    DartChunker from package:wayfinder_dart_chunker.
  final registry = ChunkerRegistry()
    ..registerChunker(TypeScriptChunker())
    ..registerChunker(MarkdownChunker());

  final files = Directory('src')
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
    final chunked = registry.chunkFiles(files).toList();
    await pipeline.ingest(chunked);

    // 3. Search the dense vectors.
    final searcher = ContentSearcher(store: store, embedder: embedder);

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
Generic dense search filters ranked candidates and doubles
its fetch window up to 32 times the requested limit; selective filters can
therefore return fewer results even when more matches exist deeper in the store.

Ingestion deduplicates chunk ids across both stored data and the current call.
An existing chunk still receives a missing embedding for the active source/model.
Metadata-only updates are persisted without regenerating vectors. Changed text needs a new chunk
ID; ingestion does not remove obsolete chunks automatically. Delete those
chunks explicitly or rebuild a fresh store when synchronizing changed files.

For generic search, an empty-result check rejects eligible content with no
compatible vectors. Successful ANN queries do not scan the whole collection or
verify partial coverage; ingestion callers own that boundary. The OKF adapter
checks every eligible passage before ranking. Missing models and incompatible
vectors never trigger another retrieval method.

## Composing searchers

`ContentSearcher` and `RerankingContentSearcher` implement `Searcher`, so they
compose without adapters. Generic custom searchers remain supported.

```dart
// Cross-encoder precision stage over any first-pass searcher.
final reranked = RerankingContentSearcher(
  searcher: denseSearcher,
  reranker: TeiReranker(baseUrl: Uri.parse('http://127.0.0.1:8080')),
  candidateLimit: 50,
);

// Small-to-large: match precise child chunks, present the enclosing context.
final contextual = ParentChildSearcher(
  searcher: denseSearcher,
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
  The installer pins native 5.3.2, verifies the release archive's SHA-256
  before extracting it, and writes only to this package's `lib/` directory.
  It covers every platform upstream publishes for
  5.3.2 - macOS universal, linux x64/aarch64/armv7hf/armv6hf and windows
  x64/x86/arm64 - and refuses anything without a pinned hash rather than
  installing another architecture.
  The package accepts any Dart `objectbox` 5.x from 5.3.2. The repository's
  workspace overrides it to 5.3.2, so its tests and native bundles always pair
  Dart 5.3.2 with native 5.3.2, and `test/objectbox_assets_test.dart` fails
  when the two differ.
  `test/objectbox_store_test.dart` skips itself when the library is absent.
  `minimumSearchCandidates` defaults to 50 independently of the result limit,
  trading extra work for the recall measured on the fixture corpus.

Both implement `BaseStore`. `storeBatch` writes chunks and embeddings together;
`ObjectBoxStore` overrides it with one transaction.
Memory search uses cosine similarity, returns zero for zero vectors, and scales
finite vectors before scoring to avoid numeric overflow or underflow.

## Local examples and fixtures

Run it from the package directory:

```bash
dart run example/basic_example.dart
```

It previews a checked-in `fixtures/samples/` file without loading a model and
creates no searchable index. The sample corpus covers the three built-in
chunkers, including plain text and Markdown table examples inside code fences.
Markdown code blocks retain literal table syntax; actual tables inherit their
heading metadata and are omitted when `includeTables` is false. The Dart sample
and its code example moved to
[`wayfinder_dart_chunker`](../wayfinder_dart_chunker/README.md).

The sample corpus has its own golden snapshot. The separate `fixtures/corpus/`
retrieval benchmark retains its recorded queries and metrics.

## Local model and builds

The package pins `llamadart` 0.8.23 and Arctic Embed XS Q8_0: a 25,279,840-byte
GGUF producing 384-dimensional vectors. Development and CLI builds need Dart
3.11.0+, the minimum every package in the workspace declares. The pinned
llamadart release requires only 3.10.7, so the declared floor sits above it.
Build hooks and `dart build cli` were introduced in Dart 3.10; the tested Dart
3.11 CLI still labels its bundle command as preview.

From the repository root:

```bash
melos run wayfinder_embeddings:prepare
melos run objectbox:install
melos run wayfinder_embeddings:build
```

The prepare step uses llamadart's shared download cache, an immutable revision,
and SHA-256 verification. It stages `models/embedding.gguf` and a manifest;
weights stay out of Git. `objectbox:install` verifies its pinned release archive
the same way, so every native asset a bundle ships is checked against a recorded
hash. From this package, add `--offline` to
`dart run tool/prepare_model.dart` or `dart run tool/build_wayfinder_embeddings.dart` to
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

The build creates `build/wayfinder_embeddings/bundle/` with an executable under `bin/`,
native libraries under `lib/` (ObjectBox's DLL is beside the executable on
Windows), and weights, manifest, license, and attribution under `models/`.
Distribute the whole bundle. Runtime model lookup uses the executable location,
then the development `models/` directory; `WAYFINDER_EMBEDDING_MODEL` or the
CLI's `--model` can override it. Runtime inference never downloads weights.

`LlamaEmbedder.open()` verifies the file before loading. It owns the engine;
call `dispose()` in a `finally` block. A backend that never reports itself
started is retried once on a fresh engine, because the first load from a
freshly installed bundle can exceed the runtime's fixed worker startup timeout
while the operating system validates the native libraries. `coldStartRetries`
reports whether that happened, and the comparison CLI prints it, so a slow
first load is visible instead of inferred. Documents use their
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
The committed bindings come from `objectbox_generator` 5.3.2 and keep every id
and UID 0.2.0 used, so a store 0.2.0 wrote opens unchanged.
`test/objectbox_store_test.dart` opens such a store from
[`test/fixtures/objectbox-0.2.0/`](test/fixtures/objectbox-0.2.0/README.md).

Run `dart run example/native_example.dart` after preparing the model.
Generic Markdown chunking preserves caller-supplied metadata; an OKF adapter
still needs to parse and supply the concept metadata.

## Custom chunkers and embedders

Extend `BaseChunker` or `BaseEmbedder`. Register a chunker with
`ChunkerRegistry` so files route to it by content type or extension. Override
`BaseEmbedder.generateEmbeddings` when the backend accepts a batch.

## Evaluation

The retrieval benchmark and the genuine dense regression gate live in `tool/`;
their fixtures and judgments live in [`fixtures/`](fixtures/README.md). Run from
this package after preparing the model:

```bash
dart test test/fixtures_pipeline_golden_test.dart test/retrieval_fixture_gate_test.dart
dart run tool/compare_embeddings.dart \
  --embedders=dense --store=memory --top=10 \
  --long-input=truncate \
  --reference-chunks=test/goldens/baseline_chunks.json \
  --queries=fixtures/corpus/retrieval_queries.json \
  --qrels=fixtures/corpus/retrieval_qrels.json \
  --query-groups=fixtures/corpus/retrieval_query_groups.json \
  --metrics-output=comparison_results/dense_metrics.json \
  --baseline-metrics=fixtures/benchmarks/dense_metrics_baseline.json
```

The gate allows absolute drops of 0.05 Recall@10 and 0.03 nDCG@10 by default.
Update goldens with `UPDATE_GOLDENS=1` only after reviewing the content change.

The judged corpus is mostly Dart, and this package has no Dart chunker.
`--reference-chunks` replays the corpus golden's chunks for every file no
built-in chunker handles, so the gate keeps the chunk ids the qrels name;
TypeScript and Markdown files still go through their chunkers. With `--qrels`,
`compare_embeddings` exits with an error instead of scoring when a fixture file
has no chunker or, with stable-id matching, when a judged chunk id is missing
from the corpus, so a run without `--reference-chunks` cannot report collapsed
recall. The golden tests and `tool/validation.dart` replay the same golden.
`wayfinder_dart_chunker`'s `test/judged_corpus_test.dart` is the corpus
golden's only writer: it checks that its chunker still produces those Dart
chunks and rewrites the whole golden with `UPDATE_GOLDENS=1`, while this
package only compares against it. Budget experiments apply to the built-in
chunkers only; score them with `--qrels-match=span-overlap`.

## License

Dart package: BSD 3-Clause. See `LICENSE`. The bundled model uses Apache-2.0;
its license and conversion attribution are in `tool/model_assets/`.

## Dense-only migration

This is a breaking Dart and command-contract change, selected for product
simplicity in [ADR-0017](../../docs/adr/0017-dense-only-retrieval.md):

- Supply `embedder:` to `KnowledgeIndex` and `KnowledgeIndex.fromSnapshot`.
- Remove `KnowledgeRetrievalMode`, search `mode:`, and OKF `candidateLimit:`.
- Replace `HybridContentSearcher` with `ContentSearcher`. BM25, lexical
  tokenization, and reciprocal-rank-fusion APIs are removed without aliases.
- Use `dense` or `rerank:dense` in evaluation tools. `llamadart` remains a dense
  alias. Retired `bm25`, `lexical`, `hybrid`, and reranked variants fail explicitly.
- Remove the evaluator's `--native` and knowledge example's `--dense` toggles;
  both always require genuine model inference. Preview examples remain model-free.

Generic `Searcher`, reranking, TEI endpoints, reranker candidate limits, parent/child
expansion, storage, and context policy remain available.
Model-load errors fail, and the OKF adapter rejects missing eligible vectors.

The cutoff does not change model identity, input format, snapshot format, or
store schema. Compatible existing saved indexes remain usable. Independent
changes to contextual input or an opt-in chunking policy still have their own
rebuild requirements. No bundle or Profile migration is introduced.
