# OKF retrieval component experiment

Recorded 2026-09-09 on Apple M2 Max, Dart 3.11.0, llamadart 0.8.23,
Arctic Embed XS Q8_0, ObjectBox Dart 5.0.4/native 5.3.2. These findings bind
neither OKF nor the Concepta profile. No priority or credibility field is added.

## Protocol and selection

The synthetic fixture contains 34 actual OKF concepts, producing 37 passages,
and 35 questions. Before retrieval, questions were split into 18 development
and 17 held-out cases, each including one unanswerable question. Relevance
requires both the correct concept path and a supporting text fragment. Each
query gets three context slots. History intent and path scopes are fixed
inputs across all configurations.

Seven configurations isolate body text, title/heading context, lifecycle,
explicit governing sources, one-hop declared relationships, and combinations.
All use identical BM25/dense/RRF settings; dense scoring covers every eligible
vector. Query judgments, corpus, and model were not tuned after measurement.

Development results selected context + current lifecycle (except historical
queries) + explicit governors + bounded one-hop relationships before the
held-out split was run. BM25 remains the model-free default; semantic retrieval
is opt-in. The API leaves policy explicit rather than assuming all consumers
want current guidance or the same authority order.

The [checked-in results](../packages/wayfinder_embeddings/fixtures/benchmarks/okf_ablation_results.json)
record query/corpus hashes, per-query correctness, group metrics, timings,
and both stores. Full generated reports additionally include cited passages,
match order, inclusion reasons, and notices. The original 65-query corpus and
the earlier 13 direct-chunk diagnostics are separate and unchanged.

## Results

Cells show **correct first context passage / answerable questions; support
recall@3**. These measure assembled context, not only raw similarity ranking:
governing-source policy deliberately changes context order. MemoryStore and
ObjectBox produced identical quality metrics in every configuration.

### Development (17 answerable)

| Configuration | BM25 | Dense | Hybrid |
| --- | --- | --- | --- |
| Body | 7/17; 58.8% | 6/17; 88.2% | 7/17; 64.7% |
| Title/heading context | 11/17; 88.2% | 10/17; 94.1% | 11/17; 94.1% |
| Lifecycle only | 7/17; 58.8% | 10/17; 88.2% | 9/17; 64.7% |
| Governing sources only | 9/17; 64.7% | 8/17; 88.2% | 9/17; 70.6% |
| Relationships only | 7/17; 70.6% | 6/17; 88.2% | 7/17; 76.5% |
| Combined without links | 14/17; 88.2% | 15/17; 94.1% | 14/17; 94.1% |
| Combined | 14/17; 94.1% | 15/17; 100% | 14/17; 100% |

### Held out (16 answerable)

| Configuration | BM25 | Dense | Hybrid |
| --- | --- | --- | --- |
| Body | 11/16; 87.5% | 13/16; 93.8% | 12/16; 87.5% |
| Title/heading context | 13/16; 87.5% | 13/16; 100% | 13/16; 87.5% |
| Lifecycle only | 12/16; 87.5% | 14/16; 100% | 13/16; 87.5% |
| Governing sources only | 12/16; 87.5% | 13/16; 93.8% | 13/16; 87.5% |
| Relationships only | 11/16; 87.5% | 13/16; 100% | 12/16; 93.8% |
| Combined without links | 14/16; 87.5% | 15/16; 100% | 14/16; 87.5% |
| Combined | 14/16; 93.8% | 15/16; 100% | 14/16; 93.8% |

Combined MRR on held-out cases is 0.896 BM25, 0.969 dense, and 0.906 hybrid.
The gains do not imply every addition helps every query:

- Links recover the development quarantine answer in every combined mode.
  On held-out queries they recover quarantine replay for BM25/hybrid; dense
  already retrieves it. They cause no regressions relative to combined without
  links here. Relationships alone slightly reduce development dense MRR.
- Combined dense moves held-out `repeated-key` from first to second compared
  with body-only dense. Better aggregate results can still hide regressions.
- Every configuration/mode returns three candidates for each unanswerable
  question. There is no measured abstention mechanism or calibrated confidence.
- Explicit authority mapping is supplied by the consumer. Type, verification,
  recency, and similarity do not establish a universal precedence order.

These small synthetic splits justify retaining configurable components, not a
claim of real-world superiority. Do not promote hybrid by default: the separate
65-query corpus still has a TypeScript recall regression relative to BM25.

## Cost and store choice

The model-free example does not open an encoder or create vectors. Semantic
modes use the existing verified 25.28 MB artifact; they do not use Ollama or
fetch a model during runtime. One engine is reused, passages are encoded in
batches, and up to 100 query vectors are cached per index.

The held-out native evaluation opened its model in 1.389 seconds. Contextual
synchronization of 37 passages took 76.8 ms in memory and 71.1 ms in ObjectBox.
These are sequential JIT observations with warmed native code, not controlled
first-build or cold-start comparisons. This native evaluation builds vectors
even for its BM25 rows to share the same corpus projection; its synchronization
numbers therefore do not represent model-free ingestion cost.

Warm held-out combined query p50/p95 was 0.126/0.218 ms for BM25 and
0.286/0.901 ms for dense in memory; ObjectBox dense was 0.853/1.079 ms. Query
vectors were already cached, so these numbers exclude new-query inference.
They were recorded before removing unnecessary lexical scoring from dense-only
search. Do not infer a production speedup or store ranking from 37 passages.

Choose ObjectBox for persistence, transactions, and indexed vector identity
lookups. It did not improve relevance. The adapter deliberately uses exact
cosine over eligible vectors to prevent selective-filter misses; work grows
linearly with that set. Large-corpus native scalar indexes and ANN strategies
need a separate measured experiment. Existing build/startup measurements and
cache behavior remain in the [local-search report](wayfinder_embeddings_local_search.md).

## Reproduce

From `packages/wayfinder_embeddings`:

```bash
# No model or native database required:
dart run example/knowledge_example.dart
dart run tool/evaluate_okf_retrieval.dart --stores=memory --split=development --output=comparison_results/okf-bm25.json

# After model preparation and ObjectBox installation:
dart run example/knowledge_example.dart --dense
dart run tool/evaluate_okf_retrieval.dart --native --split=development --output=comparison_results/okf-development.json
dart run tool/evaluate_okf_retrieval.dart --native --split=held_out --output=comparison_results/okf-held-out.json
```

Native CI runs both splits and uploads full reports. The checked-in experiment
records results, rather than declaring all models must exceed a newly selected
aggregate threshold. Unit/native tests enforce citation preservation, lifecycle
and scope eligibility, bounded relationships, explicit governors, atomic
replacement, model isolation, unchanged-vector reuse, and real tokenizer
budgets. Two fixture regression tests also check every BM25 component's per-query
results across both splits. The original corpus retains its independent promotion gate.
