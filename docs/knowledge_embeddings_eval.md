# Knowledge Embeddings Evaluation

This note is the runbook and the evidence ledger for retrieval quality in
`packages/knowledge_embeddings`. It records how to run the benchmark, the current
metrics, the results that did not earn a default, and the work that stays
deferred.

Status on 2026-09-08: defaults are unchanged. Exact BM25 is the CI gate. Dense
and hybrid runs need a local Ollama daemon and are not part of CI.

## The corpus and the gate

The corpus is `packages/knowledge_embeddings/fixtures/corpus`. It mixes Dart,
TypeScript, Markdown, and text so every built-in chunker is exercised. Beside
the sources it holds:

- `retrieval_queries.json` - query id to query text.
- `retrieval_qrels.json` - BEIR-style judgments, `{query_id: {stableId: 0..3}}`,
  keyed by the fixture-relative `stableId` so ids survive a different checkout
  path.
- `retrieval_query_groups.json` - query id to driver surface (`dart`,
  `typescript`, `markdown`), so a per-language regression cannot hide behind a
  flat aggregate.
- `bm25_metrics_baseline.json` - the checked-in BM25 baseline the gate reads.
- `nomic_dense_hybrid_metrics_baseline.json`,
  `embeddinggemma_dimension_metrics_baseline.json`, and
  `qwen3_dimension_metrics_baseline.json` - recorded local-model evidence. CI
  does not read these.

`test/retrieval_fixture_gate_test.dart` runs the BM25 gate inside the package
test suite. Run the same check from the command line with:

```bash
melos exec --scope=knowledge_embeddings -- dart run tool/compare_embeddings.dart \
  --embedders=bm25 --store=memory --top=10 \
  --queries=fixtures/corpus/retrieval_queries.json \
  --qrels=fixtures/corpus/retrieval_qrels.json \
  --baseline-metrics=fixtures/corpus/bm25_metrics_baseline.json
```

The checked-in qrels set is a local fixture benchmark, not a universal search
quality benchmark. Use it to catch regressions in chunking and exact lexical
retrieval.

## Benchmark options

`tool/compare_embeddings.dart` ingests the corpus once per run descriptor and
writes chunks, embeddings, query vectors, search results, and a Markdown
summary under `--output`.

| Option | Meaning |
| --- | --- |
| `--fixtures=DIR` | Corpus folder. Defaults to `fixtures/corpus`. |
| `--output=DIR` | Artifact folder. Defaults to `comparison_results`. |
| `--embedders=LIST` | Comma-separated run descriptors. See below. |
| `--queries=FILE` | Query id to text mapping. Required with `--qrels`. |
| `--qrels=FILE` | BEIR-style judgments. Enables the metrics report. |
| `--query-groups=FILE` | Query id to group name. Falls back to `retrieval_query_groups.json` next to the qrels file. |
| `--qrels-match=stable-id\|span-overlap` | How a qrels id resolves to a chunk. |
| `--top=K` | Result cutoff. |
| `--candidates=N` | First-pass window before fusion or reranking. |
| `--chunk-budget=N` | Non-whitespace budget for every chunker. |
| `--dart-chunk-budget`, `--typescript-chunk-budget` (`--ts-chunk-budget`), `--markdown-chunk-budget`, `--text-chunk-budget` | Per-chunker budgets. These win over `--chunk-budget`. |
| `--store=memory\|objectbox` | Backing store. `objectbox` needs `melos run objectbox:install` and accepts 768-dimensional vectors only. |
| `--reranker-url=URL` | TEI-compatible `/rerank` endpoint. Required for `rerank:` runs. |
| `--reranker-timeout-seconds=N` | Per-request reranker timeout. Default 30. |
| `--metrics-output=FILE` | Write the metrics report. Requires `--qrels`. |
| `--baseline-metrics=FILE` | Fail when metrics drop below a baseline. Requires `--qrels`. |
| `--max-recall-drop`, `--max-ndcg-drop`, `--max-mrr-drop` | Gate thresholds. Defaults 0.05, 0.03, and off. |
| `--validate-golden` | Compare the chunk manifest with the golden snapshot first. |
| `--skip-comparison` | Exit before any work runs. |

Run descriptors:

- `bm25` (or `lexical`) - exact `BM25LexicalIndex`, no vectors.
- `hybrid` - BM25 fused with the default dense model through RRF.
  `hybrid:<model>` targets another Ollama model.
- `ollama:<model>` - dense only. Short aliases: `nomic`, `qwen3`.
- Append `@<dimensions>` to any model to ask the runtime for a reduced output,
  for example `ollama:qwen3@768` or `hybrid:embeddinggemma@256`.
- `rerank:<descriptor>` - add a cross-encoder stage over any of the above.

`span-overlap` matters for chunk-budget experiments: a different budget changes
chunk ids, so the tool resolves the stable qrels ids against the default
reference chunks and scores candidates by fixture-relative path and line
overlap. Keep `stable-id` for the CI gate, where boundaries must not move.

## Chunk manifest golden

`tool/validation.dart` runs the chunkers over the corpus, compares the chunk
manifest with `test/goldens/baseline_chunks.json`, and writes BM25 search
artifacts under `validation_results/`.

```bash
melos exec --scope=knowledge_embeddings -- dart run tool/validation.dart

# After an intentional fixture or chunker change:
UPDATE_GOLDENS=1 \
  melos exec --scope=knowledge_embeddings -- dart run tool/validation.dart
```

## Current metrics

All rows use the 65-query grouped fixture, top 10, `MemoryStore`, candidate
depth 50, and `--qrels-match=span-overlap`. Dense and hybrid rows were captured
on 2026-06-16 with a local Ollama daemon; compare them within this table only.

| Candidate | Retriever | Recall@10 | nDCG@10 | MRR |
| --- | --- | ---: | ---: | ---: |
| Default registry | BM25 | 0.942 | 0.886 | 0.915 |
| Default registry | nomic dense | 0.947 | 0.869 | 0.914 |
| Default registry | nomic hybrid | 0.962 | 0.915 | 0.962 |
| Default registry | embeddinggemma dense | 0.967 | 0.813 | 0.841 |
| Default registry | embeddinggemma hybrid | 0.977 | 0.915 | 0.959 |
| Default registry | Qwen3 dense | 0.954 | 0.837 | 0.899 |
| Default registry | Qwen3 hybrid | 0.985 | 0.886 | 0.920 |

Chunk-budget candidates, BM25 only:

| Candidate | Recall@10 | nDCG@10 | MRR |
| --- | ---: | ---: | ---: |
| Default registry | 0.942 | 0.886 | 0.915 |
| Shared budget 600 | 0.927 | 0.917 | 0.965 |
| Shared budget 800 | 0.935 | 0.905 | 0.944 |
| Shared budget 1000 | 0.942 | 0.893 | 0.926 |
| Shared budget 1200 | 0.942 | 0.890 | 0.918 |
| Shared budget 1600 | 0.942 | 0.886 | 0.915 |

Hybrid RRF is the best configuration on this fixture for every tested model.
BM25 alone is close enough that it remains the CI gate.

## Recorded negative results

These were measured and did not earn a default change.

- **Chunk budgets.** Shared budget 600 leads ranking quality but loses about
  1.5 recall points. Shared 800 recovers part of that and still trails the
  default by about 0.8 recall points. The best hybrid budget disagrees by model
  family: `embeddinggemma` favors 600, `nomic-embed-text` favors 800, and Qwen3
  keeps maximum recall at the default. One fixture cannot settle that. The
  default registry and shared 1600 tie because Dart's default is already 1600.
  TypeScript and Markdown subgroups did not move; the Dart subgroup drove every
  difference.
- **Document overlap.** A 1-line overlap between adjacent Markdown and text
  paragraph chunks left BM25 metrics unchanged at shared budgets 600 and 800.
  The overlap chunker and its command-line flags were removed on 2026-09-08;
  this row is the reason.
- **Client-side MRL truncation.** A hand-maintained table of per-model
  truncation dimensions plus client-side re-normalization was replaced by the
  server-side `dimensions` field of `/api/embed`. The recorded 512 and 256
  dimension baselines stay in `fixtures/corpus` as evidence.
- **Reranking.** The runtime boundary exists as `TeiReranker`, but the local
  matrix has never run: no TEI-compatible service, `docker`, or
  `text-embeddings-router` was available in this workspace. Reranking is opt-in
  and has no recorded lift on this corpus.

## Reranker matrix

Run this once a TEI-compatible service is reachable. Check first:

```bash
curl --max-time 2 http://127.0.0.1:8080/health
```

```bash
melos exec --scope=knowledge_embeddings -- dart run tool/compare_embeddings.dart \
  --embedders=bm25,rerank:bm25,hybrid:embeddinggemma,rerank:hybrid:embeddinggemma \
  --store=memory --top=10 --candidates=50 \
  --reranker-url=http://127.0.0.1:8080 \
  --reranker-timeout-seconds=120 \
  --queries=fixtures/corpus/retrieval_queries.json \
  --qrels=fixtures/corpus/retrieval_qrels.json \
  --metrics-output=comparison_results/reranker_matrix/metrics.json \
  --output=comparison_results/reranker_matrix
```

`TeiReranker` posts `{"query": "...", "texts": [...]}` and expects a JSON list
of objects with an integer `index` and a finite numeric `score`. A runtime may
return only a top-scored subset; omitted candidates get no synthetic score.
Malformed, duplicate, or excess indexes are rejected.

Reranking becomes a default only when the local matrix shows that:

- aggregate Recall@10, nDCG@10, and MRR do not regress past the gate
  thresholds;
- no query group regresses behind a flat aggregate;
- each reranked run beats its own first-pass baseline, not a public benchmark;
- the added latency fits the intended workflow.

## Model licensing

The package accepts Apache-2.0 or MIT models only. The strongest small code
embedders (`SFR-Embedding-Code`, `jina-code-embeddings`) and
`jina-reranker-v3` are CC-BY-NC and are therefore out of scope.

| Model | Dim | License | Available through |
| --- | ---: | --- | --- |
| `embeddinggemma` | 768 | Gemma terms, on-device | Ollama (package default) |
| `nomic-embed-text` v1.5 | 768 | Apache-2.0 | Ollama |
| `qwen3-embedding:0.6b` | 1024 | Apache-2.0 | Ollama (code-tuned) |
| `bge-reranker-v2-m3` | - | Apache-2.0 | TEI |
| `Qwen3-Reranker-0.6B` | - | Apache-2.0 | TEI |

Published code-retrieval benchmarks (CoIR, MTEB-Code) rank code-tuned models
well above general text models, which is why `qwen3-embedding:0.6b` is the
recommended code embedder. Do not treat those numbers as a decision on their
own: the acceptance gate is this fixture.

## Design decisions this evidence supports

- **Keep AST chunking with non-whitespace budgets.** cAST (Zhang et al.,
  Findings of EMNLP 2025) measures chunk size in non-whitespace characters and
  reports +4.3 Recall@5 on RepoEval over line-based splitting. The package
  follows that unit.
- **Keep lexical and dense separate and fuse at query time.** Reciprocal Rank
  Fusion with k=60 (Cormack, Clarke & Büttcher, SIGIR '09) is rank-based, so it
  sidesteps the BM25-to-cosine scale mismatch. An earlier design hashed BM25
  weights into a 768-dimensional dense vector; that discarded exact-match
  strength and scored differently per store. It was removed.
- **Keep `MemoryStore` as a supported backend.** At single-repository scale,
  brute-force search gives full recall with no index build cost.
- **Keep the qrels gate.** Every claim above is a fixture measurement, and the
  gate is what stops a silent regression.

## Deferred

- **Late chunking.** It preserves cross-chunk context but needs a long-context
  token-embedding model with pooling control that Ollama's endpoint does not
  expose.
- **Runtime ObjectBox dimensions.** The generated HNSW entity fixes 768
  dimensions at code-generation time. Other dimensions need `MemoryStore`, or a
  new entity plus a migration path.
- **Tree-sitter chunkers.** The Dart package naming has settled but
  `tree_sitter_language_pack` is still a prerelease.
- **Broader qrels.** Changing a built-in chunk budget needs a second corpus,
  per-language drivers, and dense or hybrid coverage. One fixture is not
  enough.
