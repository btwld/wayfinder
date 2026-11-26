# Fixtures

The protocols and full measurements behind the recorded results are kept at
commit `7728c1f`: the [component experiment](https://github.com/btwld/wayfinder/blob/7728c1f/docs/wayfinder_embeddings_ablation.md),
the [model-free versus local embedding benchmark](https://github.com/btwld/wayfinder/blob/7728c1f/docs/wayfinder_embeddings_comparison.md),
and the [small-model comparison](https://github.com/btwld/wayfinder/blob/7728c1f/docs/wayfinder_embeddings_model_comparison.md).

## corpus/

Mixed Dart, TypeScript, and Markdown sources with 65 queries (`retrieval_queries.json`),
graded relevance judgments (`retrieval_qrels.json`), and surface groups
(`retrieval_query_groups.json`). Keep non-corpus files outside `corpus/`: the
chunk golden test processes every `.dart`, `.ts`, `.tsx`, `.md`, `.markdown`,
and `.txt` file under that root.

`test/retrieval_fixture_gate_test.dart` checks structural fixture integrity and
slice coverage without loading a model. It is not a relevance gate. Genuine
dense relevance against `benchmarks/dense_metrics_baseline.json` runs in the
native CI job when the local model is prepared.

The committed baseline chunks in `test/goldens/baseline_chunks.json` are the
source of truth for every corpus file. This package has no Dart chunker; its
tools and tests replay the baseline's Dart chunks (`--reference-chunks`), so the
qrels keep naming the chunks they were judged against. Tests compare against
the baseline but never rewrite it, even with `UPDATE_GOLDENS=1`. Review any
intended baseline change together with every qrels id that moved.

## okf_retrieval/

34 synthetic OKF concepts and 35 passage-judged questions cover lifecycle,
explicit governing sources, heading context, and declared links. The development
and held-out splits contain 18 and 17 questions. This unprofiled fixture is not
a normative bundle template. Do not adjust judgments to fit model output.

`dart run tool/evaluate_okf_retrieval.dart --output=REPORT` requires the local
model. `knowledge/*` runs search through `KnowledgeIndex`, which scores every
stored vector in Dart, for each context-policy variant; their cutoff is the
fixture's three context slots. `findSimilar/*` runs query the stored body and
context vectors through the store's own `findSimilar` at ten results, so
approximate native search is measured, and compare each list with exact cosine
ranking (`exactRecall`, `maxScoreDelta`). Both report recall, MRR, nDCG and
top-1. The Drift and ObjectBox packages have the same tool for their stores.
The 37 passages are fewer than ObjectBox's candidate floor, so the fixture checks
the ObjectBox result path but cannot exercise its HNSW approximation.
See the [evaluation guide](../README.md#evaluation).

The protocol at `7728c1f` records dense combined development recall@3 of 100%.
The current 94% comes from the labelled `okf-context-v2` input of `9891dba`: it
moves `guidance/queue-retry.md` 0.0015 cosine ahead of `guidance/payments.md`
for the `negation` question, and the declared link from `queue-retry.md` then
takes the last context slot.

## knowledge_retrieval/

`cases.json` holds 13 synthetic chunks and 13 judged questions. Cases include
scope, authority conflicts, stale guidance, paraphrases, negation, missing
verification, and an unanswerable question. Metadata is caller-projected.

`dart run tool/evaluate_knowledge_cases.dart REPORT` requires the local model
and evaluates dense retrieval with the memory store. These diagnostics are separate
from the 65-query corpus gate.

## embedding_comparison/

100 synthetic concepts and 160 topic-separated questions retain frozen support
judgments. The [fixture notes](embedding_comparison/README.md) state the known
annotation limits. Current benchmark runners use dense retrieval only.

`tool/benchmark_retrieval.dart` reports raw matches and assembled context at
ten slots, with recall@3, recall@10, MRR and first-result correctness for the
60 answerable questions of a split. For the 20 unanswerable questions it
counts those that still returned candidates and records each query's top
similarity. With `--iterations=0` it skips the latency loops.

The [protocol at `4ebf6a6^`](https://github.com/btwld/wayfinder/blob/4ebf6a6%5E/docs/wayfinder_embeddings_comparison.md)
recorded held-out dense context results of 50/60 first passages, 88.3%
recall@3, 91.7% recall@10 and MRR 0.863, with candidates for every
unanswerable question. On the current `okf-context-v2` passages they are 52/60,
90.0%, 93.3% and 0.887. Development moved from 52/60, 91.7%, 96.7% and 0.902
to 50/60, 88.3%, 90.0% and 0.863. Unanswerable questions still all return
candidates; retrieval does not abstain.

## samples/

Reusable example inputs exercise the three built-in chunkers, including code
fences and Markdown tables.
Preview examples read these files without changing them.
`test/fixtures_pipeline_golden_test.dart` checks corpus and sample chunk content,
line ranges, metadata, and portable identities. LF line endings are preserved.

After reviewing an intended chunk change, regenerate the sample snapshot from
the package directory; the committed corpus baseline stays unchanged:

```sh
UPDATE_GOLDENS=1 dart test test/fixtures_pipeline_golden_test.dart
```

The sample corpus is independent of the historical 65-query relevance baseline.

## benchmarks/

`dense_metrics_baseline.json` contains the existing dense row from the committed
2026-09-09 native baseline. Its `provenance` records the original commit, path,
checksum, and omitted configuration key. This extraction changes no metric or
judgment and is not a new evaluation. Its original model identity predates the
current identity spelling; the gate compares metric drops, not that old string.
The original run used the recorded truncation policy. Do not present its results
as current accuracy on a different corpus, chunk policy, or model.

`embedding_comparison_baseline.json` holds the 160-query fixture's raw and
context recall@3, recall@10 and MRR per split for the memory store, checked
the same way through `tool/benchmark_retrieval.dart --baseline`.

`okf_retrieval/` holds one baseline per store for the OKF fixture's recall,
MRR and, for `findSimilar/*` runs, `exactRecall` on both splits, recorded on
Linux x64. `--baselines` fails a run that drops more than 0.01 below any of
them, or whose model or queries differ. Refresh a store's file with
`--update-baselines` only after reviewing the per-query change.

Obsolete multi-method reports are retired from the active tree. Their committed
originals remain in Git history; current reproduction uses the [evaluation guide](../README.md#evaluation).
