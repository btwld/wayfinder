# Local knowledge search: implementation and measurements

Reviewed 2026-09-09 after the provider and fixture cleanup. This records tooling
choices and measurements; it adds no OKF or profile convention.

Keep **BM25 as the default**, provide **llamadart embeddings for optional hybrid
search**, and use **ObjectBox when persistence is needed**. ObjectBox and BM25
solve different problems: a database stores and searches vectors; BM25 ranks
text using corpus term statistics. This implementation supports both together.
The subsequent [knowledge retrieval review](knowledge_embeddings_knowledge_retrieval.md)
tests authority, lifecycle, filtering, and cases where semantic retrieval fails.
Its storage fixes preserve IDs, refresh metadata, and add an exact fallback for
underfilled ANN results within the selected model.

## Runtime and model

The package uses [`llamadart` 0.8.23](https://pub.dev/packages/llamadart/versions/0.8.23)
with llama.cpp in-process. Its public repository is maintained by
[Jhin Lee (`leehack`)](https://github.com/leehack). An embedding model is required
for these semantic vectors; BM25 needs no learned model. Hashing words into a
fixed vector would provide lexical features, not the learned semantic behavior
being evaluated here.

The pinned artifact is a community GGUF conversion of Snowflake Arctic Embed XS:

| Property | Value |
| --- | --- |
| Quantization | Q8_0 |
| Download | 25,279,840 bytes (25.28 MB / 24.11 MiB) |
| Encoder | 22.6 million parameters, 384 dimensions |
| Context | 512 tokenizer tokens, including special tokens |
| Pooling | CLS, as encoded in the GGUF metadata |
| Output | L2 normalized |
| License | Apache-2.0 |

The [original model card](https://huggingface.co/Snowflake/snowflake-arctic-embed-xs)
specifies asymmetric retrieval: passages have no prefix; queries start with
`Represent this sentence for searching relevant passages: `. The
[conversion repository](https://huggingface.co/mradermacher/snowflake-arctic-embed-xs-GGUF/tree/143419f28857ed7f3b1afd13713f3b3955231338)
provides the immutable artifact. Its SHA-256 is
`a2fe17db11616959ab2235a7727bc7d080becfe77b6ab16671b25866da8ea582`.
`EmbeddingModelSpec` is the source for build and runtime verification; filenames
remain stable and a manifest carries identity. Q4_K_M would save only about
4 MB here, so Q8_0 avoids that additional quantization tradeoff.

`LlamaEmbedder` verifies bytes before loading, owns and disposes one engine,
batches document embeddings, and prefixes queries separately. Runtime identity
includes the model specification, preprocessing revision, and token policy.
CPU inference uses four threads. Character chunk budgets remain distinct from
model token limits: oversized input is rejected by default. Explicit truncation
retokenizes the encoded prefix to check the limit and counts affected inputs.
Original chunk content and ranges are preserved.

## Download and distribution

Preparation uses llamadart's [model download manager](https://llamadart.leehack.com/docs/guides/model-lifecycle)
for the shared cache, retries, interrupted-download handling, and checksum
validation. A revision-pinned URL avoids a moving `main` artifact. The prepare
step verifies size and SHA-256 again before atomically replacing the staged
model. `--offline` allows staged/cache reuse and fails on a miss without a model
network request. Runtime inference only loads local files.

The build pins llama.cpp assets through llamadart and limits
[native hooks](https://llamadart.leehack.com/docs/platforms/native-build-hooks)
to `llama_cpp` and `cpu`. On macOS the distributed library still contains Metal;
the embedding engine explicitly selects CPU. This avoids the default additional
LiteRT-LM runtime and GPU backend bundles on platforms with separate libraries.
Native hook downloads have a separate cache from model weights.

[`dart build cli`](https://dart.dev/tools/dart-build) packages the executable
and declared native assets. `tool/build_embeddings.dart` additionally copies
the verified model, manifest, model license/attribution, and ObjectBox library.
Source development and CLI builds require Dart 3.10.7+. The whole bundle
must be distributed. On this Mac, the actual evaluator bundle is **51.96 MB**:
9.76 MB executable, 13.35 MB llamadart library, 3.56 MB ObjectBox library, and
25.28 MB weights plus small metadata files. Model size is not total install size.

Dart's [build hooks](https://dart.dev/tools/hooks) and CLI bundling appeared in
3.10. The 3.10.7 floor comes from llamadart. The tested 3.11 SDK still prints a
preview notice for `dart build cli`; the build uses no experimental flags.
Hook user-defines belong to the consuming app/workspace root, so this workspace
keeps the llama.cpp/CPU selection only in its root pubspec. Consumers must set
their own selection; a dependency cannot impose these settings on an app.

GGUF weights are data. The [data_assets package](https://pub.dev/packages/data_assets)
remains experimental, and the [Dart 3.11 implementation](https://github.com/dart-lang/sdk/blob/3.11.0/pkg/dartdev/lib/src/native_assets.dart)
enables it behind a separate experiment. Keeping model acquisition and copying
in our explicit packaging command avoids depending on that experiment. Only the
native llama.cpp library is emitted as a bundled code asset by llamadart's hook.
ObjectBox's installed library is copied explicitly because the pinned package
uses its conventional native-library installation path.
The installer pins the tested Dart 5.0.4 / native 5.3.2 pair and the upstream
download script's release tag. It downloads in a temporary directory so repeated
installation cannot block on an archive overwrite prompt. The earlier installer
followed a moving `main` script; native-library updates are now explicit.

The packaged CLI loads its model and ObjectBox library relative to the executable.
A relocated copy completed all three retrieval modes from an empty working
directory using absolute corpus/output paths. No source-checkout library or
working-directory model was required. Linux/macOS CI now builds and exercises
this path; those remote jobs have not been run from this local workspace.

## Retrieval quality after cleanup

Measured on the unchanged 20-file, 350-chunk, 65-query synthetic corpus, using
stable-id qrels, top 10 results, and 50 hybrid candidates. One 580-token Dart
chunk was explicitly truncated to fit the encoder. The checked-in
[local baseline](../packages/knowledge_embeddings/fixtures/benchmarks/local_metrics_baseline.json)
records model identity, token policy, aggregate metrics, and language slices.

| Retrieval | Memory Recall@10 | ObjectBox Recall@10 | nDCG@10, both | MRR, both |
| --- | ---: | ---: | ---: | ---: |
| BM25 | 0.9423 | 0.9423 | 0.8862 | 0.9154 |
| Dense | 0.9538 | 0.9538 | 0.8380 | 0.8678 |
| Hybrid RRF | **0.9705** | **0.9705** | **0.9174** | **0.9615** |

Equal metrics do not imply identical candidate lists or a general exact-search
guarantee. ObjectBox uses [approximate HNSW search](https://docs.objectbox.io/on-device-vector-search).
The first dense run used only ten HNSW candidates and reached 0.9077 recall /
0.7986 nDCG. A configurable 50-candidate minimum recovered the metrics above.
The result limit remains ten. This is a measured precision/latency choice for
this corpus; evaluate it again as the corpus grows.

Hybrid improves aggregate results but TypeScript recall falls from BM25's 1.0
to 0.9048 across seven queries. That exceeds the existing 0.05 allowed drop.
Dense also weakens ranking quality despite slightly higher aggregate recall.
Therefore neither replaces the BM25 default gate. The independent native CI
gate checks each native mode against its own recorded baseline; it does not
assert that hybrid has earned promotion over BM25.

## Storage cost

Apple M2 Max, macOS ARM64, Dart 3.11 AOT. The storage benchmark reused the exact
350 document vectors and 65 query vectors produced by the native comparison,
excluding inference and JSON decoding. Two full warmup passes preceded ten
measured passes (650 queries per store). Stores ran sequentially in one process;
setup timings are individual observations, not cold-disk distributions.

| Operation | MemoryStore | ObjectBox |
| --- | ---: | ---: |
| Initial open | <0.001 ms | 26.22 ms |
| Write 350 chunks + vectors | 0.56 ms | 43.85 ms |
| Reopen persisted database | N/A | 1.92 ms |
| Read all chunks | 0.013 ms | 0.79 ms |
| Build in-memory BM25 index | 8.13 ms | 7.33 ms |
| BM25 query p50 / p95 | 0.052 / 0.082 ms | 0.050 / 0.076 ms |
| Dense query p50 / p95 | 2.19 / 3.18 ms | 1.43 / 1.66 ms |
| Database file | None | 1.25 MB |

BM25 performance is effectively the same because both stores feed the same
in-memory lexical index. ObjectBox makes dense search faster in this run and
preserves data across restarts, at the cost of writes, a native library, and an
approximate index. Raw 384-dimensional float32 vectors for 350 chunks take
537,600 bytes; database size also includes chunk text, metadata, relations, and
indexes. These results do not establish performance at large corpus sizes.

Reproduce storage measurements after the native comparison in the
[evaluation runbook](knowledge_embeddings_eval.md):

```bash
# From packages/knowledge_embeddings; ObjectBox must already be installed.
dart build cli --target=tool/benchmark_stores.dart --output=build/store-benchmark
build/store-benchmark/bundle/bin/benchmark_stores \
  comparison_results/local-memory/dense comparison_results/store_cost.json
```

`dart run tool/benchmark_stores.dart ...` also works, but reports JIT timings.
Model inference, native memory use, and startup must be measured separately
from this precomputed-vector benchmark.

## Model latency and memory

Two fresh-process AOT probes of the final provider measured **18.6–19.7 seconds
for verification plus loading**, **1.93–2.24 seconds** to encode all 350 documents,
and **1.12–1.27 ms p50 / 1.74–1.95 ms p95** for the 65 query embeddings. Peak
process RSS was **238–245 MB**, including decoded corpus artifacts and vectors.
These are a pair of local observations, not a cold-start percentile benchmark;
the probes overlapped briefly, so encoding timings are indicative only.

A separate staged measurement spent 218 ms verifying the artifact and 20.14
seconds opening the provider; its first query took 2 ms. A subsequent controlled
retest launched that **same compiled executable three times sequentially, without
rebuilding**. Provider opening, including its own checksum verification, took
**734 ms, 294 ms, and 289 ms**; first queries took 4 ms, 2 ms, and 3 ms. The
executable SHA-256 was unchanged before and after the runs. Each process also
performed a separate 206–214 ms verification before opening the provider, so
these measurements follow a read of the model file in that process.

Later launches therefore improved substantially; 18–20 seconds is not the
observed steady-state launch cost. Compilation and model download were outside
all these runtime intervals. The exact cause of the initial delay remains
unresolved: the results are consistent with a first-use or cache effect, but do
not establish that it happens only once after installation or cannot return
after an update or reboot. Earlier isolated engine-only probes also loaded in
86–238 ms, excluding this provider's artifact verification.
A JIT run also reached 1.18 GB peak RSS, so development-runtime memory is not a
substitute for measuring the packaged application.

Keep one engine loaded for a search session and dispose it afterward. The CLI
only opens it for explicitly selected semantic runs; BM25 performs no inference.
The model's small download does not imply negligible initialization time or RAM.

## Migration and verification

The generated ObjectBox entity now has 384 dimensions. Existing databases from
the previous schema are rejected before opening: reindex original source files
into a fresh directory. Never relabel old vectors as the new model or pad/truncate
vectors to satisfy an index dimension. Committed ObjectBox UID history is retained.

The cleanup also moves reusable examples into fixtures, strengthens chunk
goldens, fixes pending-ingestion deduplication and failed-factory cleanup,
preserves Markdown code/table boundaries, and stabilizes cosine arithmetic.
The obsolete HTTP embedding provider, model aliases, dependency, example,
tests, and provider-specific benchmark artifacts are removed.

Unit tests cover model verification, cache/offline behavior, document/query
formatting, invalid vectors, token limits, disposal, and storage migration
protection. Actual native tests exercise model inference and ObjectBox; the
full corpus comparison and relocated CLI have also run locally. The regular
BM25 fixture remains independent of model availability.
