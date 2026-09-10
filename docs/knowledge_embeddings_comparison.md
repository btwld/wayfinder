# Model-free and local embedding benchmark

Measured 2026-09-09 on Apple M2 Max, Dart 3.11.0, llamadart 0.8.23 and
Arctic Embed XS Q8_0 (384 dimensions), ObjectBox Dart 5.0.4/native 5.3.2.
The [agreed plan](knowledge_embeddings_benchmark_plan.md) defined the comparison.
The subsequent [small-model comparison](knowledge_embeddings_model_comparison.md)
tests Arctic S and BGE-small Q8/Q4 against this XS baseline without changing
the frozen fixture or production defaults.

## Decision

Keep BM25 as the reusable adapter's default and local dense retrieval as an optional capability,
as recorded in [ADR-0009](adr/0009-local-knowledge-retrieval.md).
Dense improved the observed held-out aggregate, but its topic-based uncertainty
includes no gain and it still missed required passages on negation questions.
Hybrid did not recover most of the dense advantage. ObjectBox provides
persistence; it did not improve judged relevance and exact vector scans became
substantially slower as the corpus grew.

## Quality

The new fixture has 100 generic synthetic OKF concepts and 140 passages, with
160 questions split by topic: 80 development and 80 test questions, each split
containing 60 answerable and 20 unanswerable questions. Whole topics remain in
one split. Sources, judgments, settings, and passage identities were frozen;
no tuning followed development. The actual tokenizer verified all contextual
passages fit before measurement. Existing 65-query and 35-query fixtures remain
separate regressions, not newly untouched test sets.

All arms receive the same text, scope, lifecycle, governing map, one-hop links,
and ten available context slots. Recall@3 scores the first three slots. Raw
ranking and assembled context are reported separately. First-context correctness
is not the same as pure model ranking. Both stores and repeated process runs
produced identical per-query results.

| Held-out arm | Correct first raw match | Correct first context | Context recall@3 | Context recall@10 | Context MRR |
| --- | ---: | ---: | ---: | ---: | ---: |
| keyword | 39/60 | 46/60 | 78.3% | 80.0% | 0.777 |
| bm25 | 32/60 | 45/60 | 80.0% | 80.0% | 0.769 |
| dense | 33/60 | 50/60 | 88.3% | 91.7% | 0.863 |
| hybrid | 33/60 | 46/60 | 81.7% | 81.7% | 0.792 |

Relative to BM25, dense won ten first-context judgments and lost five, a net
8.3 percentage-point improvement. A 10,000-draw paired bootstrap clustered by
topic gives a 95% interval of **−1.7 to +18.3 percentage points**. Only ten test
topics contribute; these bounds are descriptive rather than strong evidence
of population-level improvement. Hybrid's net gain is 1.7 points, with interval
−3.3 to +6.7. All four arms returned candidates on all 20 unanswerable questions;
none establishes answerability.

The keyword control slightly exceeds BM25 first-context accuracy here, while
BM25 has higher recall@3. This is a basic distinct-term matcher using the same
tokenizer, with no IDF/frequency/length weighting. Its result is evidence against
assuming a more elaborate scorer must always win on this synthetic corpus.

### Failure review and annotation limits

Dense selects a security notice for `sessions-prohibition`, missing the required
authentication prohibition. For `locks-prohibition`, it selects lock ordering
instead of the prohibition on holding locks during network calls. One-best-
passage-per-concept selection can discard the needed section even when the
right document is found; that is a candidate for a separately measured change.

`payments-prohibition` is a known strict-judgment false negative: dense retrieves
“reuse the original idempotency key,” which supports rejecting a different key,
but the frozen judgment only credits the explicitly negative paragraph. Scores
above retain the original annotation. They must not be read as proof that every
judged miss is incorrect. A future corpus needs independent review of alternate
supporting passages. The fixture uses repeated authored templates, not client
knowledge or independent human annotation.

## Runtime cost

Each arm/store combination ran in ten fresh compiled processes. ObjectBox also
ran ten reopened-index processes. Fresh-process filesystem caches were not
flushed. The first repetition measured 1,000 uncached queries and 1,000 cache-hit
queries, with two warmup passes before cache-hit measurements. Randomized query
order and rotating arm order reduce ordering bias; this was a developer Mac,
not an otherwise idle controlled laboratory.

Model-free runs asserted no model opening, zero document/query encodings, and
zero stored embeddings. Dense/hybrid asserted 1,000 query encodings on the
uncached path and zero on the cached path. Fresh index instances clear query
caches between uncached passes without reloading the engine; their synchronization
is outside query intervals and reuses every stored vector.

| Arm/store | Fresh first result, median ms | Reopened first result, median ms | New query p50/p95 ms | Cached query p50 ms | Peak RSS, median MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| keyword/memory | 14.1 | — | 0.112/0.135 | 0.109 | 54.3 |
| keyword/objectbox | 36.7 | 17.5 | 0.107/0.132 | 0.104 | 60.1 |
| bm25/memory | 13.7 | — | 0.876/0.979 | 0.855 | 29.5 |
| bm25/objectbox | 30.4 | 16.4 | 0.868/0.975 | 0.885 | 36.7 |
| dense/memory | 517.9 | — | 2.073/2.621 | 0.847 | 171.5 |
| dense/objectbox | 582.0 | 315.0 | 4.451/5.071 | 3.087 | 181.7 |
| hybrid/memory | 527.6 | — | 2.953/3.420 | 1.622 | 172.2 |
| hybrid/objectbox | 560.5 | 316.1 | 5.347/6.049 | 4.049 | 180.7 |

Reopened runs reload the source fixture and synchronize its in-memory snapshot,
reusing saved document vectors. They do not open a complete saved knowledge
snapshot without synchronization.

First-result time starts at Dart `main` and includes fixture reads, store/model
open, parsing, initial synchronization, and the first query. Process wall time
is also recorded, but includes the entire benchmark and must not be mistaken
for startup. Peak RSS covers the complete child run, including updates; it is
not steady-state model memory alone. Per-phase encoding/read/write timings
are retained in JSON. New-query encoding itself costs about 1.2–1.3 ms median. The measured sequential
uncached loops achieved 1197 BM25 and 488 dense queries/second in memory;
the initial dense batch encoded 823 passages/second. These are this workload's
observed rates, not concurrent throughput limits.

All arms use the same adapter synchronization, which constructs a BM25 snapshot;
the keyword arm also builds its term sets. It is a diagnostic control within
this adapter, not the minimum possible implementation of plain file search.
Raw adapter search performs context assembly with policy disabled, followed by
the measured common policy assembly. `rankingAndRawContext` is labeled accordingly.

Metadata-only changes encoded zero passages in every run. Adding one body
paragraph while deleting an obsolete concept encoded one new passage in each
semantic arm and removed the obsolete chunk. Reopening an existing ObjectBox
index encoded zero passages. These assertions guard against measuring accidental
re-indexing as normal startup.

## Storage scale

The scale sweep uses deterministic precomputed synthetic 384-dimensional vectors
and unique generated passages. It measures storage/ranking cost without inference,
not semantic quality. Each size has ten queries, one warmup pass, and three
measured passes. Exact eligible-vector retrieval is compared consistently;
ANN was not introduced or measured. ObjectBox returns all eligible vectors to
Dart for scoring in this path.

| Passages | Store | Keyword p50 ms | BM25 p50 ms | Exact dense p50 ms | Hybrid p50 ms |
| --- | --- | ---: | ---: | ---: | ---: |
| 1,000 | memory | 0.27 | 0.42 | 3.31 | 3.75 |
| 1,000 | objectbox | 0.28 | 0.43 | 38.76 | 39.20 |
| 10,000 | memory | 2.93 | 5.38 | 34.50 | 39.80 |
| 10,000 | objectbox | 2.89 | 5.26 | 395.03 | 400.54 |
| 50,000 | memory | 18.70 | 32.57 | 175.45 | 208.99 |
| 50,000 | objectbox | 19.54 | 31.92 | 1940.84 | 1973.16 |

Scale runs use a shared process with sequential stores, so their peak RSS is
cumulative and cannot attribute memory to an individual store. The stress data
is synthetic; no real-world relevance gain is inferred from it. Improving the
exact scan or introducing a measured selective ANN strategy is separate work.

## Build and preparation

A temporary package copy with empty project and llamadart native caches built
in **6.18 s**; the cached rebuild took **4.89 s**.
The Dart SDK and hosted Dart-package cache were already installed. ObjectBox
native setup took 0.70 s. This is one successful pair, not a build-time distribution.
An initial harness copy mistakenly omitted source directories named `models`;
that failed attempt was fixed and excluded from successful timings.

An empty task-owned model cache required **3.80 s** to download, verify,
and stage the 25.28 MB artifact. Verified offline reuse took
**0.22 s**, with zero download bytes. Model bytes are the artifact payload,
not HTTP wire traffic. Native cache artifacts occupied 17.89 MB;
native HTTP wire bytes were not instrumented. The compiled benchmark bundle
before model/ObjectBox packaging was 21.60 MB, plus a
3.56 MB ObjectBox library and the model.

The separate compiled token-budget validation took 4.21 ms
for all 140 contextual passages. No splitting was necessary. Headline query
runs share these verified passage boundaries and exclude this preparation step;
the recorded validation run includes it in first-result time.

The currently shipped dependency graph includes native hooks even for a BM25
entrypoint. Model-free runtime does not imply a native-free build. Measurements
use task-owned caches and copies; the user's global caches were not cleared.
No new model or library was selected during these experiments.

## Reproduce and inspect

From `packages/knowledge_embeddings`, with the model prepared and ObjectBox
installed, the macOS commands used for the retrieval bundle are:

```bash
dart build cli --target=bin/benchmark_retrieval.dart --output=build/benchmark
cp -R models build/benchmark/bundle/
cp lib/libobjectbox.dylib build/benchmark/bundle/lib/
```

Then run the isolated processes:

```bash
python3 tool/run_retrieval_benchmark.py --binary=build/benchmark/bundle/bin/benchmark_retrieval --output=comparison_results/development --split=development --starts=1
python3 tool/run_retrieval_benchmark.py --binary=build/benchmark/bundle/bin/benchmark_retrieval --output=comparison_results/test --split=test --starts=10
python3 tool/summarize_retrieval_benchmark.py comparison_results comparison_results/summary.json
```

`tool/benchmark_retrieval_scale.dart SIZE OUTPUT` runs the independent scale
sweep; its matching `bin/` entrypoint supports compilation. Clean/cached build setup is reproducible with
`python3 tool/benchmark_build_setup.py --output=comparison_results`. Model preparation
has a separate `tool/benchmark_model_preparation.dart OUTPUT` command using an
empty temporary cache and then verified offline reuse.

The [fixture manifest](../packages/knowledge_embeddings/fixtures/embedding_comparison/manifest.json)
records hashes and selection. The compact checked-in
[results](../packages/knowledge_embeddings/fixtures/benchmarks/embedding_comparison_results.json)
retain per-query metrics, paired wins/losses, and cost distributions. Full cited
rankings and per-process reports are not checked in: they are several megabytes
of permanent repository weight that the commands above regenerate from the
frozen fixture. Long performance
runs remain manual; normal tests cover the shared tokenizer, passage judgments,
canonical citations, and the existing retrieval/policy contracts.

Validation: all 282 embedding tests and 33 profile tests passed; analysis reported
no issues. Existing fixture regression gates still pass. No retrieval defaults,
model choice, or profile rules changed in response to these measurements.
