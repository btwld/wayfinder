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

This package has no Dart chunker. The corpus golden,
`test/goldens/baseline_chunks.json`, keeps the chunks of every corpus file, and
the tools and tests replay its Dart chunks (`--reference-chunks`), so the qrels
keep naming the chunks they were judged against.
[`wayfinder_dart_chunker`](../../wayfinder_dart_chunker/README.md) is that
golden's only writer and checks that its chunker still produces them. This
package compares against it but never rewrites it, even with
`UPDATE_GOLDENS=1`. After an intended change to any corpus chunk, Dart or not,
rewrite it from that package with
`UPDATE_GOLDENS=1 dart test test/judged_corpus_test.dart`, then review every
qrels id that moved.

## okf_retrieval/

34 synthetic OKF concepts and 35 passage-judged questions cover lifecycle,
explicit governing sources, heading context, and declared links. The development
and held-out splits contain 18 and 17 questions. This unprofiled fixture is not
a normative bundle template. Do not adjust judgments to fit model output.

`dart run tool/evaluate_okf_retrieval.dart --output=REPORT` requires the local
model. It reports dense results for both stores and the context-policy variants.
See the [evaluation guide](../README.md#evaluation).

## knowledge_retrieval/

`cases.json` holds 13 synthetic chunks and 13 judged questions. Cases include
scope, authority conflicts, stale guidance, paraphrases, negation, missing
verification, and an unanswerable question. Metadata is caller-projected.

`dart run tool/evaluate_knowledge_cases.dart REPORT` requires the local model
and evaluates dense retrieval with both stores. These diagnostics are separate
from the 65-query corpus gate.

## embedding_comparison/

100 synthetic concepts and 160 topic-separated questions retain frozen support
judgments. The [fixture notes](embedding_comparison/README.md) state the known
annotation limits. Current benchmark runners use dense retrieval only.

## samples/

Reusable example inputs exercise the three built-in chunkers, including code
fences and Markdown tables. The Dart sample moved to `wayfinder_dart_chunker`.
Preview examples read these files without changing them.
`test/fixtures_pipeline_golden_test.dart` checks corpus and sample chunk content,
line ranges, metadata, and portable identities. LF line endings are preserved.

After reviewing an intended chunk change, regenerate the sample snapshot from
the package directory; the corpus snapshot is rewritten from
`wayfinder_dart_chunker`, as described under `corpus/`:

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

Obsolete multi-method reports are retired from the active tree. Their committed
originals remain in Git history; current reproduction uses the [evaluation guide](../README.md#evaluation).
