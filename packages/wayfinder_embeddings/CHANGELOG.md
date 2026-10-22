# 0.3.0 (unreleased)

- Requires `wayfinder` `^0.3.0`, and depends on `ack` `^1.7.0`.
- New `package:wayfinder_embeddings/knowledge_store.dart`: the index
  lifecycle `wayfinder index` and `wayfinder search` use, moved out of the
  CLI. `WayfinderKnowledgeStore` keeps saved indexes of OKF bundles in the
  data directory a host names, with `status` (missing, current, stale with
  the changed paths, or incompatible), `index` (progress events, and
  cancellation that deletes the staged generation), `search` across a
  project's bundles and `searchBundle` for one, `forget`, `prune` and
  `dispose`. Results carry typed `KnowledgeCitation`s and the CLI's JSON and
  Markdown; failures are `WayfinderException`s with stable codes. The host
  supplies a `WayfinderEncoderProvider`, such as `LocalModelEncoderProvider`
  over a model file it located, and optionally an ObjectBox loader; the store
  never locates a model or loads native code itself, and reports
  `objectbox-unavailable`, keeping ObjectBox's own hint off stdout, when
  ObjectBox's library does not load. `wayfinderSearchInput`
  and the new `knowledgeMetadataFilterInput` are the Ack inputs of a host's
  search tool.
- Indexes live in `indexes/<bundle key>/<configuration key>/`, so another
  model, chunker or format never shares a directory. An index Wayfinder 0.2
  wrote, at `indexes/<sha256 of the root>/`, is never read, changed or
  deleted; each bundle builds once after upgrading.
- The store's chunk IDs no longer depend on where a bundle lives:
  `KnowledgeSnapshot.load` and `KnowledgeSnapshot.fromSources` take an
  `idNamespace` that replaces the `bundleId` in each chunk ID, and the store
  passes a constant, so a bundle's copies in two worktrees get the same IDs
  and rank alike. The default, the `bundleId`, is unchanged.
- The store's freshness inventory leaves out okf's `.okf.lock` at any depth
  and never opens it, so a bundle that holds one indexes and searches, and
  another process's lock on it stays held.
- New `package:wayfinder_embeddings/testing.dart`: `DeterministicTestEmbedder`
  and `DeterministicEncoderProvider`, 384-dimension word-hash vectors that test
  indexing, storage and search without a model. They are no relevance
  evidence (ADR-0017).
- `knowledge_store.dart` also exports what a host names beside the store:
  `BaseEmbedder` for its own encoder provider, `Chunk` and `SearchResult` for
  a citation's passage, `EmbeddingModelSpec` and `localEmbeddingModel` for
  another model, and `KnowledgeSearchResponse` and `KnowledgeContextHit` for
  search results in a fake.
- `KnowledgeIndex.synchronize` takes `onEmbedded`, which reports the inputs
  embedded so far, and a `WayfinderCancellation` checked between batches.
  `LlamaEmbedder.source` and `LlamaEmbedder.modelNameFor` give an embedder's
  identity without loading a model.
- **BREAKING:** `defaultEmbeddingModelFile` no longer looks beside the running
  executable, so neither does `LlamaEmbedder.open()` without a `modelFile`.
  Pass `installation:`, the root of an installed bundle, to find its
  `models/`. The `compare_embeddings` and `benchmark_retrieval` native entry
  points pass their bundled model themselves.
- **BREAKING:** `DartChunker` moved to the new `wayfinder_dart_chunker`
  package, and this package no longer depends on `analyzer`, so an application
  can choose its own analyzer version. `wayfinder_embeddings.dart` no longer
  exports it. Add `wayfinder_dart_chunker` and import
  `package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart` to keep chunking
  Dart; its `defaultCodeRegistry()` registers `DartChunker` beside this
  package's TypeScript, Markdown and text chunkers. Chunks, ids and metadata
  are unchanged, so saved indexes stay valid. No deprecated alias is provided.
- The code example and the Dart sample move to `wayfinder_dart_chunker`.
  `tool/compare_embeddings.dart` drops `--dart-chunk-budget` and gains
  `--reference-chunks`, which replays a committed chunk manifest for files no
  built-in chunker handles. The judged corpus gate replays its Dart chunks from
  `test/goldens/baseline_chunks.json`, so its chunk ids, qrels and recorded
  metrics are unchanged; `wayfinder_dart_chunker` checks that its chunker
  still produces those chunks. With `--qrels`, the tool now exits with an
  error instead of scoring when a fixture file has no chunker or a stable-id
  judgment names a chunk the corpus lacks.
- Depends on `objectbox` `^5.3.2` and `flat_buffers` `^25.9.23` instead of the
  exact `objectbox` 5.0.4 pin, so applications on current ObjectBox can resolve
  this package. `lib/objectbox.g.dart` is regenerated with
  `objectbox_generator` 5.3.2. Every entity, property and index id and UID is
  unchanged, so an `ObjectBoxStore` directory written by 0.2.0 opens and keeps
  working without a reindex; a test opens one that 0.2.0 wrote. The knowledge
  store still builds each bundle once in its new layout (see above).
- Requires `okf` `^0.5.1`.
- New `package:wayfinder_embeddings/model_cache.dart` entry with
  `EmbeddingModelCache`, so an application can obtain the pinned Arctic Embed
  XS Q8_0 model itself. `target` describes the download (source URL, size,
  SHA-256, destination); `locate` finds a verified copy without touching the
  network; `provision` downloads it through an injectable `http.Client` into a
  temporary file in the cache directory, reports progress, verifies the size
  and SHA-256 before an atomic rename, and is cancellable, removing the
  temporary file. A response that announces a size other than the pinned one
  is refused before its body, and temporary files an interrupted download
  left are removed once nothing has written to them for a day. The cache
  directory is `models/<id>` in the `dataDirectory` given, by default the
  Wayfinder data directory, or any directory through
  `EmbeddingModelCache.inDirectory`. Failures are `WayfinderException`s:
  `model-download-failed`, `model-invalid`, `model-cache-unavailable` (the
  cache directory cannot be written), `cancelled`, and
  `data-directory-unavailable` from the default constructor. The entry also
  exports `WayfinderException`, `WayfinderCancellation`,
  `WayfinderCancellationController` and `WayfinderDataDirectory`, so a host
  needs no direct `wayfinder` dependency. Adds the `http` dependency.
- `tool/prepare_model.dart` downloads through `EmbeddingModelCache` instead of
  llamadart's download manager, into the cache's default directory in the
  Wayfinder data directory, and prints download progress. It still stages
  `models/embedding.gguf` and its manifest, still copies a verified model from
  the llamadart caches earlier releases filled, leaving their files there, and
  `--offline` still refuses to download. `tool/prepare_benchmark_models.dart`
  downloads each experimental model straight into its `--output` directory
  instead of llamadart's shared cache.
- **BREAKING:** depends on `llamadart` `>=0.15.6 <0.16.0` instead of the exact
  0.8.23 pin. Its build hook downloads llama.cpp from
  `leehack/llamadart-native` v0.7.0-2 (llama.cpp 620d2225) instead of v0.4.0,
  and checks each archive against the SHA-256 llamadart pins before
  extracting it.
- **BREAKING:** `LlamaEmbedder.open` loads the model with `LlamaEngine.load`
  on the CPU only (`ComputeDevice.cpu`), with the same context, batch,
  micro-batch and thread counts, and verifies the file before anything loads.
  Its `newEngine` parameter is replaced by `loadEngine`, a `LlamaEngineLoader`
  that loads the model itself and leaves nothing behind when it throws, as
  `LlamaEngine.load` does. Tokenizing, truncation, query prefixes and
  normalized vectors are unchanged. The one retry of a cold backend start
  recognises the startup timeout as llamadart 0.15 reports it, inside the
  `LlamaModelException` of the failed load.
- The knowledge store's configuration moves to version 5 and names the
  llama.cpp release Wayfinder reviewed, the new `wayfinderLlamaCppRuntime`
  (v0.7.0-2), so moving it builds every index anew. The new runtime's vectors
  differ slightly from 0.8.23's (cosine similarity of at least 0.99995 on the
  judged corpus on macOS arm64), so each bundle builds once after upgrading,
  and a version 4 index is never read. Retrieval quality is unchanged: on the
  judged corpus Recall@10 stays 0.954 and nDCG@10 moves from 0.838 to 0.839,
  and both OKF evaluation splits rank every query as before. The configuration
  names the reviewed release, not the one a host's build bundles: a host that
  shares indexes must resolve a llamadart that pins it, as the README
  describes.
- Building a native bundle fails before anything builds when the resolved
  llamadart pins a `llamadart-native` release other than
  `wayfinderLlamaCppRuntime`, or when the workspace sets
  `llamadart_native_tag`, `llamadart_native_repository` or
  `llamadart_native_path`. It accepts a Windows CPU backend module named for
  a CPU variant, such as `ggml-cpu-haswell.dll`.
- The embedding runtime's notices also attribute what llama.cpp vendors into
  the native library: cpp-httplib and JSON for Modern C++, with their licence
  texts, and stb_image, miniaudio and subprocess.h. Earlier bundles shipped
  them without these notices.
- The README's hook settings for consumers were wrong: llamadart's hook
  ignores a bare `llamadart_native_backends: [cpu]`, as 0.8.23's did, so Linux
  and Windows bundled Vulkan as well. It now selects `[cpu]` per platform.
<!--
Release bookkeeping: the bullets from "read while indexing (#110)" to the end
of this section supersede what the bullets above say about an ObjectBox
loader, `objectbox-unavailable` and the
`indexes/<bundle key>/<configuration key>/` layout. If both ship in one
release, fold these into those bullets and drop the superseded text; if the
bullets above ship first, move these under the next release.
-->
- **BREAKING:** read while indexing (#110). The knowledge store no longer
  uses ObjectBox. Each index is a sequence of immutable generations in
  `indexes/bundles/<bundle key>/<configuration key>/`:
  `generation-<id>/snapshot.json`, the record, and `vectors.f32`, a 16-byte
  header (`WFVF32\0\x01`, then the dimension and row count as little-endian
  32-bit integers) followed by one little-endian float32 row per snapshot
  chunk, in chunk order. The record names the vectors' dimension, row count,
  SHA-256 and a hash of the input each row embeds, and a reader checks them.
  An index
  publishes a complete generation by atomically replacing a `current`
  pointer. A search loads the published generation into a `MemoryStore` and
  scores every eligible passage exactly, as before: the vectors are the same
  float32 values, so rankings do not change. The configuration's `store`
  becomes `f32-v1`, so each bundle builds once. An index Wayfinder 0.2 wrote,
  or one an ObjectBox-backed store wrote in `indexes/<bundle key>/`, is never
  read, changed or deleted, by `forget` and `prune` included.
  `WayfinderKnowledgeStore` drops `loadObjectBox` and the
  `objectbox-unavailable` code, and accepts an encoder of any dimension.
  `ObjectBoxStore` stays in `wayfinder_embeddings.dart` for custom retrieval
  workflows; the store does not use it.
- Only writers lock. `index` and `forget` hold the index's `writer.lock`, in
  its directory, across isolates and processes, and a second writer still
  fails with `index-busy`. `status`, `search` and `searchBundle` hold no
  lock, so they keep working while an index runs, and never read a partial
  generation. They probe the writer lock for an instant
  (`WayfinderFileLock.isHeld`), which a starting writer waits out instead of
  failing with `index-busy`. On Windows, which replaces no file another
  handle has open, a publication waits up to two seconds for readers that
  have the `current` pointer open, then fails with `index-busy` and keeps the
  published generation; a reader that cannot read the pointer reads it again
  after a short wait. A superseded generation stays for the new `gracePeriod` (10
  minutes by default) after the publication that replaced it and goes with a
  later publication; a reader that loses that race reads the pointer again
  instead of failing. A search or `status` records the index's use on the
  lock file, which `prune` compares with its period.
- `search` and `searchBundle` take a `StaleIndexPolicy`. `refuse`, the
  default, refuses a stale index as before. `serveWhileRefreshing` serves the
  last published generation while another operation holds the writer lock:
  the result adds a `refresh-in-progress` notice and, for files edited since,
  a `source-changed` notice; `KnowledgeCitation.sourceChanged` marks their
  passages, which the JSON adds as `"sourceChanged": true` and the Markdown as
  `source changed` in the citation's bracket. While a bundle's first index is
  being built, such a search fails with `index-busy`. Results gain
  `freshness` (`KnowledgeSearchFreshness`: `refreshing` and `changedPaths`).
- **BREAKING:** the sealed `KnowledgeIndexStatus` gains
  `KnowledgeIndexRefreshing`, which `status` reports, with the published
  generation's status, while a writer runs. An exhaustive `switch` over a
  status must handle it.
- With `retainEncoder`, operations no longer run one at a time. They share one
  encoder, and each call into it, a batch of passages, a query vector or a
  token count, waits for the previous one, so a search runs between an
  index's batches and two calls never use one model at once. A failed
  encoder is disposed once no operation uses it.
- `prune` also deletes the `get` locks of project roots that no longer exist
  (`WayfinderProfileResolver.pruneProjectLocks`) and model downloads abandoned
  at least a day ago (`EmbeddingModelCache.removeAbandonedDownloads`, which
  covers every model directory under `models/`). `KnowledgePruneResult` gains
  `projectLocks` and `downloads`.
- **BREAKING:** search notices are typed. `KnowledgeSearchResponse.notices`,
  `KnowledgeBundleSearch.notices` and `KnowledgeProjectSearch.notices` are
  lists of the new `KnowledgeNotice` instead of strings: a stable `code`
  (`KnowledgeNoticeCode`, whose `wireValue` is `unresolved-relationship`,
  `governing-source-unavailable`, `refresh-in-progress` or
  `source-changed`), the `message`, a sentence for a reader without the code
  or the bundle's name, the bundle-relative `paths` it concerns (the matches
  whose link did not resolve, the governing source, or every changed file,
  not only the ten the message names), the link `target` of an unresolved
  relationship, and in a project search the `bundle`. `text` is the line
  printed before: the `refresh-in-progress` and `source-changed` lines still
  start with their code, and a project search's with the bundle's name. A
  host tells notices apart by `code` instead of by a text prefix.
  `toJson()` and `toMarkdown()` are unchanged, and so are the CLI's and MCP
  server's output. One notice is reported per sentence, as before; an
  unresolved target several matches link to now names each of them in
  `paths`. Construct `KnowledgeSearchResponse` with `KnowledgeNotice`s.
- **BREAKING:** `search` and `searchBundle` take a `WayfinderCancellation?
  cancel`, so a subclass that overrides them, as a host's test double may,
  must add the parameter. It is checked before each bundle, before the
  encoder is opened and the query encoded, and before the passages are
  scored. A cancelled search throws `cancelled`, whose message names no
  bundle, and keeps a retained encoder and its parsed snapshots.
  `KnowledgeIndex.search` takes one too, checked before it encodes the query
  and before it scores.
- `WayfinderKnowledgeStore.releaseEncoder()` disposes a retained encoder once
  the operations using it finish, and keeps the parsed snapshots; the next
  index run or search opens another. The new `encoderIdleTimeout`, with
  `retainEncoder`, does the same once no index run or search has used the
  encoder for that long, so a long-lived host frees the model's memory
  without disposing the store. `status`, `forget`, `prune` and an index that
  finds its index current use no encoder and never keep it open.
- `EmbeddingModelCache.remove()` deletes the model at the target, verified or
  not, and the temporary files of this cache's downloads, offline, and
  returns their paths. It fails with `model-cache-unavailable`, deleting no
  model, when something other than a file or link is at the target or the
  model cannot be deleted.
- `forget` also deletes each index's `writer.lock`, while holding it, and
  the directories that leaves empty, instead of leaving them for `prune`. An
  operation that opened a lock file just before locks its path again, so it
  still excludes the next. A lock file whose index could not be deleted
  entirely, as when a reader on Windows has a generation open, stays for a
  later `prune`, which now keeps such a lock file too.
- New `WayfinderKnowledgeStore.forgetProjectRoot(root)` forgets every bundle
  at or inside a project root, found by the bundle root each index's
  `writer.lock` records, so a host can remove a deleted worktree's indexes
  without its bundle list. It returns the bundle roots it forgot, and throws
  `index-busy`, deleting nothing, while an operation indexes one of them, or
  holds an index whose recorded root cannot be read. Windows reads no held
  lock file, so there it is busy while any bundle that has no other
  configuration's index is being indexed, whichever project it belongs to.
  An index whose lock records no root, as an interrupted writer can leave,
  is not found; while its configuration is the store's, `prune` keeps it
  too, and `forget` of its bundle deletes it. A blank root, which would name
  the working directory, is refused.
- `EmbeddingModelSpec.verify` names no command (ADR-0018): a missing model
  throws `EmbeddingModelMissingException`, still a `FileSystemException`,
  whose message is `Embedding model is missing.` instead of advice to run
  Melos, and other bytes `EmbeddingModelMismatchException`, still a
  `FormatException`. Each carries an `EmbeddingModelRemedy`
  (`provide-model`) for a host to word. `knowledge_store.dart` and
  `model_cache.dart` export the three. The `wayfinder` command's output is
  unchanged: it reports the provider's `model-missing` and `model-invalid`
  with its own advice, as before.

# 0.2.0

- **BREAKING:** Dense-only retrieval replaces the former BM25/hybrid paths.
  Supply `embedder:` to both `KnowledgeIndex` constructors; remove
  `KnowledgeRetrievalMode`, search `mode:`, and OKF `candidateLimit:`.
  Remove lexical tokenization, BM25, hybrid searcher, and reciprocal-rank-fusion
  APIs without deprecated aliases. Use `ContentSearcher` instead.
- Keep generic `Searcher`, reranking, `rerank:dense`, TEI, and reranker candidate
  limits. Evaluation defaults to `dense`; retired descriptors fail before work.
  Actual evaluators always load the model; remove their `--native` toggle and
  the knowledge example's `--dense` toggle. Basic/code examples and validation
  are explicitly preview-only. Fixture gates remain structural; native CI owns
  genuine dense relevance checks against an extracted historical dense baseline.
- Fail actual OKF search when eligible passages lack compatible vectors. Generic
  search detects an empty compatible embedding space without scanning successful
  ANN queries; callers still own partial vector coverage. No model, snapshot,
  input identity, storage schema, context, or chunking change is implied by this
  cutoff. Compatible saved indexes remain usable.
- `OkfLinkField` names a producer frontmatter key whose entries are typed
  links, and `okfFieldEdges` resolves them as okf resolves a link target.
  Both live in `package:wayfinder`, which this package now depends on;
  `okf_knowledge.dart` no longer exports them.
  `KnowledgeSnapshot.load`, `fromSources`, and `fromMap` accept
  `linkFields`; search expansion follows the resulting
  `KnowledgeSnapshot.fieldEdges` before okf's untyped edges and reports each
  on `KnowledgeContextHit.fieldEdge`. Without link fields nothing changes.

Breaking API placement cleanup with a hard cutoff; no deprecated aliases or
compatibility wrappers are provided:

- Replace `EmbeddingEntity.computeKey(...)` with
  `embeddingIdentityKey(...)`.
- Replace `chunkFiles(registry, files, ...)` with
  `registry.chunkFiles(files, ...)`.
- Replace `deterministicChunkId(...)` with `Chunk.computeId(...)`.
- Replace `ReciprocalRankFusion.defaultRankConstant` with
  `defaultReciprocalRankConstant`, and `ReciprocalRankFusion.fuse(...)` with
  `fuseReciprocalRanks(...)`.
- Replace `RetrievalEvaluator.evaluate(...)` with
  `RetrievalEvaluation.evaluate(...)`, and `.evaluateQuery(...)` with
  `QueryRetrievalEvaluation.evaluate(...)`.
- Replace `RetrievalRegressionGate.evaluate(...)` with
  `RetrievalRegressionGateResult.evaluate(...)`.
- Replace `prepareFixtureConfig(...)` with `FixtureConfig.prepare(...)`, and
  `runPreview(...)` with `PreviewResult.fromFiles(...)`.
- Replace `RetrievalEvaluator.summarizeGroups(...)` with the top-level
  `summarizeRetrievalQueryGroups(...)` orchestration helper.
- Replace `ObjectBoxStore(...)` with `ObjectBoxStore.open(...)`.
- Replace `KnowledgeIndex.openSnapshot(...)` with
  `KnowledgeIndex.fromSnapshot(...)`.

# 0.1.1

- Recover oversized embedding inputs with lossless Unicode-safe subdivision and
  conditional derived-context omission in the shared OKF fitter.
- Keep whitespace attached to nonblank text and recheck the full token budget,
  avoiding blank-input failures after context omission or in body-only fitting.
- Persist effective inputs and original-chunk recovery attribution; expose immutable
  aggregated diagnostics across reopening and tighter-budget refitting. Source
  files, strict encoder rejection, model identity, and storage schema are unchanged.

# 0.1.0

- Depend on `okf` ^0.5.0, which reads every timestamp as an ISO 8601 datetime
  with an explicit UTC offset and compares `stale_after` as an instant rather
  than a local calendar day.
- Raise the Dart floor to 3.11.0, matching every Concepta package. The pinned
  `llamadart` 0.8.23 requires 3.10.7, so the declared floor now sits above what
  the dependencies strictly need.

# 0.0.1

Stable release for the Wayfinder package split; retrieval APIs are unchanged.

# Changelog

## 0.0.1-dev.0 — wayfinder_embeddings

- Introduce the Wayfinder library package, replacing knowledge_embeddings.
- Preserve existing ObjectBox databases using compatible old/new schema markers.
- Add WAYFINDER_EMBEDDING_MODEL with the legacy override as a fallback.
- Reuse verified legacy model caches, including offline preparation.

## History before the package rename

The entries below describe releases of `knowledge_embeddings`.

## 0.0.1-dev.1

- Update library documentation and application links for the Wayfinder rename.

## 0.0.1-dev.0

- Verifies the pinned ObjectBox release archive by SHA-256 before any of its
  bytes reach the package, replacing the upstream download script, with a
  pinned hash for every platform upstream publishes and no architecture
  fallback.
- Keys stored vectors on the model's bytes and preprocessing contract only, so
  another mirror of the same verified artifact reuses them.
- Retries a cold native backend start once, because the first load from a
  freshly installed bundle can exceed the runtime's worker startup timeout, and
  reports the retry count through `LlamaEmbedder.coldStartRetries`.
- Chunks Markdown footnote definitions as `footnote` apparatus and keeps them
  out of OKF passages, where attribution resolves through `sources`.
- Regenerates raw per-process benchmark reports instead of checking in
  multi-megabyte archives; summaries and provenance stay in `fixtures/`.
- Records the accepted local model/defaults and measured improvement priorities
  in ADR-0009, with available CLI commands and their current scope.
- Adds repeatable Arctic XS/S and BGE-small model comparisons, with pinned Q8/Q4
  experimental artifacts, per-model tokenizer validation, and isolated indexes.
- Adds isolated keyword/BM25/dense/hybrid benchmarks over 160 topic-separated
  questions, plus compiled startup/cache/update, build, and 1k–50k storage sweeps.
- Shares the lexical tokenizer and canonical context assembly with diagnostic
  rankers, preserving scope and original citation text for external rankings.

- Adds an upstream-OKF adapter with original citations, contextual token-budget
  splitting, explicit lifecycle/scope/governing/link policy, and atomic bundle
  synchronization that reuses unchanged vectors.
- Measures seven retrieval configurations over separate development and held-out
  fixture queries with BM25, local dense, and hybrid modes on both stores.

- Chunks Dart, TypeScript, Markdown, and text files into stable, addressable
  segments with line ranges and symbol metadata.
- Ranks chunks with exact BM25, local llamadart vectors, and Reciprocal Rank
  Fusion, with optional reranking and parent/child expansion.
- Stores chunks and embeddings in `MemoryStore` or the optional 384-dimension
  `ObjectBoxStore`.
- Ships a 65-query qrels fixture, a checked-in BM25 metrics baseline, and a
  regression gate test over `fixtures/corpus`.
- Keeps reusable example inputs in `fixtures/samples`, with full chunk goldens
  for both corpora and portable fixture paths and line endings.
- Deduplicates pending ingestion batches, releases benchmark resources after
  factory failures, and preserves Markdown code/table boundaries and headings.
- Computes stable cosine similarity for very large and very small finite vectors.
- Tokenizes each BM25 document once and removes redundant forwarding and copying
  in model, embedder, storage, and workflow paths.
- Pins a 25.28 MB Arctic Embed XS Q8_0 model; verifies size and SHA-256,
  separates query/document encoding, and rejects token overflow by default.
- Stages cached model downloads during preparation and bundles weights, native
  libraries, manifest, and model license with the retrieval CLI.
- Protects existing databases from incompatible vector-schema changes; reindex
  source files into a fresh directory.
- Exercises the selected store for lexical benchmarks as well as semantic runs.
- Preserves supplied Markdown metadata and refreshes metadata during ingestion
  without re-encoding unchanged content.
- Preserves ObjectBox entity IDs on updates, deletes chunks/vectors atomically,
  rejects invalid float32 vectors, and falls back to exact scoring within a
  model when ANN filtering leaves too few usable results.
- Adds 13 diagnostic knowledge cases for authority, lifecycle, freshness,
  paraphrases, negation, explicit scopes, and unanswerable questions.
- Initial package release; provides the retrieval implementation used by Wayfinder.
