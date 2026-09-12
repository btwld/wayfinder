# Knowledge retrieval evaluation

Run from `packages/wayfinder_embeddings/`. This is implementation evidence,
not an OKF or profile rule. BM25 remains the reusable adapter's default and
independent regression gate. The [documentation guide](wayfinder_embeddings.md)
maps the experiments and the [accepted decision](adr/0009-local-knowledge-retrieval.md)
records the model choice.

## Fixtures and checks

`fixtures/corpus/` contains 20 synthetic Dart, TypeScript, and Markdown files,
350 default chunks, and 65 judged queries (50 Dart, 7 TypeScript, 8 Markdown).
Queries, query groups, qrels, and `bm25_metrics_baseline.json` are checked in.
Qrels use fixture-relative stable chunk ids, independent of checkout location.
The baseline corpus and judgments remain unchanged by the native runtime change.

`fixtures/samples/` holds reusable example inputs moved from `example/` and its
inline TypeScript setup, plus a Markdown table/code-fence case. Both corpora
have goldens covering full content, ranges, types, metadata, and stable ids.
Fixture text uses LF endings across platforms.

```bash
dart test test/fixtures_pipeline_golden_test.dart test/retrieval_fixture_gate_test.dart
```

Only update goldens after reviewing the content change:

```bash
UPDATE_GOLDENS=1 dart test test/fixtures_pipeline_golden_test.dart
```

## BM25 gate

```bash
dart run tool/compare_embeddings.dart \
  --embedders=bm25 --store=memory --top=10 \
  --queries=fixtures/corpus/retrieval_queries.json \
  --qrels=fixtures/corpus/retrieval_qrels.json \
  --validate-golden \
  --metrics-output=comparison_results/bm25_metrics.json \
  --baseline-metrics=fixtures/corpus/bm25_metrics_baseline.json
```

The gate checks aggregate and per-group metrics. Defaults allow absolute drops
of 0.05 Recall@10 and 0.03 nDCG@10. `--max-mrr-drop` enables an MRR gate.
Changing chunk budgets requires `--qrels-match=span-overlap`; stable-id matching
is the default and is required for direct baseline comparisons.

## Native comparison

Prepare the local model, then compare three retrieval methods over both stores:

```bash
dart run tool/prepare_model.dart
# Install the ObjectBox native library from the repository root first:
# melos run objectbox:install
for store in memory objectbox; do
  dart run tool/compare_embeddings.dart \
    --embedders=bm25,dense,hybrid --store="$store" \
    --output="comparison_results/local-$store" \
    --top=10 --candidates=50 --long-input=truncate \
    --queries=fixtures/corpus/retrieval_queries.json \
    --qrels=fixtures/corpus/retrieval_qrels.json \
    --metrics-output="comparison_results/local-$store/metrics.json"
done
```

Use fresh output directories when the corpus changes: persistent stores retain
existing chunks. BM25 now writes and reloads chunks through the chosen store,
so `--store=objectbox` exercises persistence for every retrieval mode.

The corpus has one oversized 580-token chunk under the pinned model's tokenizer.
The explicit truncation option preserves the existing qrels and chunk ids for
this comparison, while encoding only a prefix of that chunk. Default native
behavior rejects oversized inputs. `model.json` records the exact model,
preprocessing identity, token policy, and truncation count for each native run.

Supported descriptors are `bm25` (`lexical`), `dense` (`llamadart`), and `hybrid`.
`rerank:<descriptor>` adds the existing optional TEI reranker and requires
`--reranker-url`; it is outside this local-model comparison. `--model=FILE`
selects a local copy of the pinned artifact, not an arbitrary model. The library
API supports a custom `EmbeddingModelSpec`; ObjectBox still requires 384 dimensions.

Each run exports chunks, document/query vectors, and search results. A summary
reports ranking overlap; metrics use graded qrels, not overlap as a proxy for
quality. Group mappings are discovered beside the qrels or supplied through
`--query-groups`. Read the [implementation report](wayfinder_embeddings_local_search.md)
for the measured results and the choice of defaults.

## Packaged evaluator

With Dart 3.11.0+ and the ObjectBox library installed:

```bash
dart run tool/build_wayfinder_embeddings.dart
```

Move the complete `build/wayfinder_embeddings/bundle/` directory to test relocation.
Invoke `bundle/bin/compare_embeddings` with absolute paths for fixtures,
queries, qrels, and outputs. The bundled model and native libraries resolve
relative to the executable. Golden validation is a source-checkout check;
its snapshots are not distributed with the executable.

CI runs deterministic tests on the minimum SDK and stable. A separate native
job prepares the model, runs actual inference/ObjectBox tests, builds the CLI,
and checks the relocated bundle against `fixtures/benchmarks/local_metrics_baseline.json`
on Linux and macOS. That baseline checks each mode against its recorded behavior;
it does not replace the independent BM25 promotion gate.

## Knowledge context cases

Run `dart run tool/evaluate_knowledge_cases.dart OUTPUT` for BM25 without a
model, or append `--native` to compare all three modes with memory and ObjectBox.
The 13 cases cover lifecycle, authority, freshness, scope, negation, paraphrases,
and an unanswerable query. Native preparation requirements are the same as
above. CI uploads the per-case JSON as a diagnostic artifact. The
[knowledge retrieval review](wayfinder_embeddings_knowledge_retrieval.md)
explains the observed failures and distinguishes caller-supplied scope from
automatic knowledge interpretation.

## OKF component comparisons

The separate [OKF adapter experiment](wayfinder_embeddings_ablation.md) compares
seven configurations on fixed development and held-out questions. It reports
passage-level context correctness with and without embeddings on both stores.
It does not replace this corpus or its promotion gate.

## Isolated retrieval and model benchmarks

The [four-arm report](wayfinder_embeddings_comparison.md) compares keyword,
BM25, local embeddings and hybrid on 160 synthetic questions, with isolated
model-free processes and separate new-query/cache-hit measurements. The
[five-model report](wayfinder_embeddings_model_comparison.md) reuses that
fixture to compare Arctic XS/S and BGE-small. Their reproduction sections own
the compiled benchmark commands and raw-artifact locations.

Reopened-index measurements in those reports reload the source fixture and
call `synchronize`, verifying zero document encodings with compatible cached
vectors. They are not a standalone saved-snapshot search benchmark. Query
caches are per index instance; a fresh CLI process must encode its query.
