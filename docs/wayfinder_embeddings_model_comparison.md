# Small local embedding model comparison

This follow-up compares Arctic Embed XS Q8_0 (the existing default), Arctic
Embed S Q8_0 and Q4_K_M, and BGE-small-en-v1.5 Q8_0 and Q4_K_M. Gemma is excluded.
The experiment does not change the production model or retrieval defaults.

## Decision

Accepted in [ADR-0009](adr/0009-local-knowledge-retrieval.md), including the
retrieval defaults, lessons, next experiments and criteria for reopening.

Keep Arctic Embed XS Q8_0 for the local embedding capability. On this fixture,
the larger Q8 models tie its first-context score, have lower recall@10, require
about 11.5 MB more weights, and take about 1.6 times as long per new memory-store
query. Q4 is slower still on this CPU/runtime. BGE Q4 saves only 0.47 MB against
XS and loses one additional first-context judgment. Arctic S Q4 gains one
recall@3 case but loses one recall@10 case against XS; that small tradeoff does
not justify its observed latency and size costs here.

This selects a practical default for the measured synthetic workload. It does
not establish that XS is universally more accurate. No Anago/client corpus was
read or evaluated in this experiment. Real-corpus relevance review and improved
passage selection remain necessary before making broader claims.

## Fixed protocol

Use the existing frozen 100-concept, 140-passage, 160-query fixture and its
original judgments without retuning. Report its development and test partitions
separately. The test partition was inspected in the previous experiment: this
follow-up is exploratory model selection, not a new untouched holdout.

Every artifact is revision-pinned and verified by byte count and SHA-256. The
upstream [Arctic](https://huggingface.co/Snowflake/snowflake-arctic-embed-s) and
[BGE](https://huggingface.co/BAAI/bge-small-en-v1.5) model cards prescribe CLS
pooling, normalized vectors and a query-only retrieval instruction. All candidates
use 384 dimensions and a 512-token context. Check the actual GGUF pooling metadata
and validate all 140 contextual passages with each model's tokenizer before
timed measurement; reject overlength input instead of truncating.

Run dense and hybrid retrieval for every model, plus keyword and BM25 controls,
through the same compiled llamadart CPU implementation (four threads). Use both
memory and ObjectBox stores with isolated per-model databases. Measure one
development process and ten test processes per combination, including ObjectBox
reopening. The first fresh process measures 1,000 uncached and 1,000 cached
queries. Rotate case/store ordering, run processes sequentially, and retain
per-query results and process-level timing. Filesystem caches are not flushed.

Compare first raw-match correctness separately from first assembled-context
correctness, recall@3/@10, MRR, paired wins/losses, and topic-cluster bootstrap
intervals. Measure verified model bytes, model opening, first result, query
latency, initial encoding, peak whole-process RSS and index reuse. Preserve
the known strict-annotation and one-passage-per-concept limitations described
in the [original results](wayfinder_embeddings_comparison.md).

## Quality

All repeated processes and both stores produced identical per-query results.
Each partition contains 60 answerable and 20 unanswerable questions. The table
reports the test partition's answerable questions.

| Embedding-only model | Verified MB | First raw match | First context | Context recall@3 | Context recall@10 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Arctic XS Q8_0 | 25.28 | 33/60 | 50/60 | 88.3% | 91.7% |
| Arctic S Q8_0 | 36.69 | 34/60 | 50/60 | 88.3% | 88.3% |
| Arctic S Q4_K_M | 29.08 | 34/60 | 50/60 | 90.0% | 90.0% |
| BGE-small Q8_0 | 36.81 | 33/60 | 50/60 | 88.3% | 90.0% |
| BGE-small Q4_K_M | 24.81 | 33/60 | 49/60 | 88.3% | 90.0% |

The keyword and BM25 controls reproduce 46/60 and 45/60 first-context results.
Hybrid first-context results are 46/60 for XS, 45/60 for S Q8, 46/60 for S Q4,
46/60 for BGE Q8 and 47/60 for BGE Q4. None exceeds its model's dense result.

On the separate development partition, dense first-context scores are XS 52/60,
S Q8 and Q4 50/60, BGE Q8 51/60 and BGE Q4 49/60. That partition does not show
a consistent advantage for either larger model, either.

Relative to XS, each larger Q8 model has two wins and two losses in first-context
judgments. Each has a zero-point net difference with a descriptive 95% paired
topic-bootstrap interval of −6.7 to +6.7 percentage points. Arctic S Q4 has the
same interval; BGE Q4 has one win and two losses, net −1.7 points with interval
−6.7 to +3.3. These use 10,000 draws over ten topics, without correction for
the multiple exploratory comparisons. They do not demonstrate equivalence or
rule out a difference on independently annotated real knowledge.

### Review of changed results

Both Arctic S variants win `payments-follow` (look up the original receipt)
and `locks-prohibition` (never hold a database lock during an external call)
against XS. They lose `releases-meaning` (rollback after failed health checks)
and `notifications-meaning` (retry a temporary delivery failure). The first
loss retrieves cache-version guidance; the second retrieves queue quarantine.
An unchanged total therefore hides two fixes and two regressions.

BGE Q8 wins `sessions-follow` (notify the account owner) and `payments-follow`,
but loses `exports-conflict` and `notifications-meaning`. On the export question,
the chosen passage is just a follow-up link instead of the short-lived URL
guidance. This exposes the existing one-passage-per-concept selection limitation;
finding the right document does not guarantee the required passage survives
context selection. BGE Q4 has the same two losses and only the payments win.

These are retrieval judgments, not generated-answer accuracy. All models return
candidates for every unanswerable query. The original strict-annotation false
negative remains unchanged, and no model-specific relevance threshold was tuned.

## Query cost

Measured on Apple M2 Max, Dart 3.11.0, llamadart 0.8.23, CPU with four threads,
ObjectBox Dart 5.0.4/native 5.3.2. These are complete adapter query timings for
140 passages, including common policy assembly. Each cell comes from 1,000
queries in the first fresh test process; startup distributions are separate.

| Embedding-only model | Memory new query p50/p95 ms | Memory cached p50 ms | ObjectBox new query p50/p95 ms | ObjectBox cached p50 ms |
| --- | ---: | ---: | ---: | ---: |
| Arctic XS Q8_0 | 2.05 / 2.57 | 0.84 | 4.66 / 5.26 | 3.19 |
| Arctic S Q8_0 | 3.28 / 4.07 | 0.85 | 5.82 / 6.72 | 3.18 |
| Arctic S Q4_K_M | 6.60 / 8.74 | 0.82 | 9.15 / 11.28 | 3.11 |
| BGE-small Q8_0 | 3.34 / 4.27 | 0.88 | 5.65 / 6.76 | 3.35 |
| BGE-small Q4_K_M | 6.70 / 8.64 | 0.89 | 9.16 / 11.75 | 3.19 |

Memory-store query encoding alone takes 1.20 ms median for XS, 2.47 ms for
both larger Q8 models, and 5.71–5.82 ms for Q4. Q4 is slower in this CPU/runtime
configuration despite using smaller artifacts; this is not a universal claim
about quantization. Cached queries do not encode text, so their costs are close.
The ObjectBox path still scores all eligible vectors exactly in Dart, as in the
original benchmark. This comparison does not introduce ANN.

Initial encoding of 140 passages in the first memory process takes 158 ms with
XS, 383 ms with S Q8, 806 ms with S Q4, 317 ms with BGE Q8 and 812 ms with BGE Q4.
These first-batch figures are individual observations, not repeated medians.

## Startup, memory and reuse

The table shows the empirical p50 of ten fresh test processes per combination;
ObjectBox also has ten reopened-index processes. First-result timing starts at
Dart `main` and includes fixture reads, verified model opening, parsing, index
synchronization and the first query. It excludes build and download time.
Filesystem caches were warm; these are fresh processes, not cold disk boots.

| Embedding-only model | Memory first result ms | ObjectBox first result ms | ObjectBox reopened ms | Memory peak RSS MiB | ObjectBox peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Arctic XS Q8_0 | 488.9 | 508.3 | 305.3 | 171.0 | 183.2 |
| Arctic S Q8_0 | 776.0 | 791.0 | 409.1 | 192.2 | 203.4 |
| Arctic S Q4_K_M | 1139.7 | 1191.9 | 333.5 | 169.3 | 181.2 |
| BGE-small Q8_0 | 768.8 | 802.9 | 420.5 | 192.3 | 204.8 |
| BGE-small Q4_K_M | 1149.8 | 1218.1 | 306.7 | 165.1 | 174.7 |

Peak RSS covers the whole child process, including quality queries, cache
warmup and updates. It is not the model's standalone RAM requirement. Model-file
sizes above use decimal MB; RSS uses MiB. Model opening includes SHA-256 checks.
These observations come from a developer Mac, not a controlled isolated lab.

Reopened processes reload sources and synchronize the knowledge snapshot using
saved vectors; the complete snapshot is not reopened directly from storage.
Every reopened index encoded zero initial passages. Every metadata update
encoded zero passages. Adding one paragraph and deleting one obsolete concept
encoded one passage in semantic modes and removed one chunk. Every uncached
semantic loop performed exactly 1,000 query encodings; cached loops performed
zero. Keyword/BM25 controls opened no model and encoded no vectors.

## Artifacts and validation

The run produced 396 measured process reports (36 development, 360 test), plus
five tokenizer-validation reports. All 140 passage inputs fit each model with
no truncation. Verified GGUF metadata reports CLS pooling for every artifact.

- [Summary and per-query metrics](../packages/wayfinder_embeddings/fixtures/benchmarks/model_comparison_results.json)
- [Artifact, binary, source and protocol provenance](../packages/wayfinder_embeddings/fixtures/benchmarks/model_comparison_provenance.json)
- Raw reports and cited passages stay out of the repository; the commands under
  [Reproduce](#reproduce) emit them from the frozen fixture and pinned models.

All 282 embedding package tests pass; Dart analysis reports no issues and the
changed Dart files pass formatting. No production retrieval behavior, model
default, ObjectBox schema, profile rule or frozen relevance judgment changed.

## Reproduce

From `packages/wayfinder_embeddings`, with the Dart workspace resolved and
ObjectBox installed, prepare the experiments outside the application's assets:

```bash
dart run tool/prepare_benchmark_models.dart --output=../../.context/model-comparison/models
dart build cli --target=bin/benchmark_retrieval.dart --output=build/model-benchmark
cp lib/libobjectbox.dylib build/model-benchmark/bundle/lib/
```

Before measurement, run each model through the compiled tokenizer check. For
example (repeat for each prepared model ID):

```bash
build/model-benchmark/bundle/bin/benchmark_retrieval --arm=dense --store=memory --split=development --iterations=0 --verify-token-budget --model=arctic-embed-s-q8_0 --model-file=../../.context/model-comparison/models/arctic-embed-s-q8_0/embedding.gguf --database=../../.context/model-comparison/unused --output=../../.context/model-comparison/validation-arctic-embed-s-q8_0.json
```

Then run the processes sequentially:

```bash
python3 tool/run_retrieval_benchmark.py --binary=build/model-benchmark/bundle/bin/benchmark_retrieval --models-directory=../../.context/model-comparison/models --output=../../.context/model-comparison/development --split=development --starts=1
python3 tool/run_retrieval_benchmark.py --binary=build/model-benchmark/bundle/bin/benchmark_retrieval --models-directory=../../.context/model-comparison/models --output=../../.context/model-comparison/test --split=test --starts=10
python3 tool/summarize_retrieval_benchmark.py ../../.context/model-comparison ../../.context/model-comparison/summary.json --models
```

The library copy above is for macOS; Linux uses `libobjectbox.so`. Model files
are downloaded only during preparation. Verified offline preparation is
available with `--offline`; retrieval itself never downloads weights. Each
experimental model requires an explicit model file, which is checked against
its pinned specification before native loading. Existing XS-only benchmark
commands remain available without `--models-directory`.
