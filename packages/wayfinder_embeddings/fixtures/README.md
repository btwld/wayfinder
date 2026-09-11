# Fixtures

## embedding_comparison/

100 synthetic concepts and 160 questions, split by topic before retrieval.
The four-arm benchmark compares keyword matching, BM25 with no model, local
dense, and hybrid. A known strict-support annotation limitation is documented
in the fixture README. Results and executable/source provenance live in
`benchmarks/embedding_comparison_*`. Per-process raw reports are regenerated
from the benchmark commands rather than checked in.
See [measured costs and quality](../../../docs/wayfinder_embeddings_comparison.md).

## okf_retrieval/

34 synthetic OKF concepts and 35 passage-judged questions, divided into 18
development and 17 held-out questions before evaluation. This is an unprofiled
retrieval fixture, not a normative bundle template. It tests lifecycle, explicit
governing sources, heading context, and declared links using the real OKF parser.
Do not adjust judgments to fit model output. See the
[protocol and measured results](../../../docs/wayfinder_embeddings_ablation.md).
`benchmarks/okf_ablation_results.json` records both stores and all seven
configurations, including per-query correctness. Native CI retains full rankings.

## knowledge_retrieval/

`cases.json` contains 13 synthetic chunks and 13 judged questions, including
authority conflicts, current/history scopes, stale guidance, paraphrases,
negation, missing verification, and an unanswerable question. Metadata is
caller-projected; this is not an example conformant bundle. Run
`dart run tool/evaluate_knowledge_cases.dart OUTPUT [--native]` from the package
directory. Native mode compares BM25, dense, and hybrid with both stores.
These diagnostic cases are separate from the unchanged 65-query corpus gate.

## corpus/

`corpus/` is the local retrieval corpus. It mixes Dart, TypeScript, and Markdown
to exercise retrieval across those surfaces. The chunk golden test and the
BM25 regression gate both target this folder.

The corpus also holds the retrieval benchmark artifacts:

- `retrieval_queries.json` - query ids mapped to human-readable query text.
- `retrieval_qrels.json` - BEIR-style qrels ("query relevance judgments") keyed
  by the fixture-relative `stableId` emitted in comparison artifacts, with
  graded relevance from 0 to 3.
- `retrieval_query_groups.json` - query ids grouped by driver surface
  (`dart`, `typescript`, `markdown`) so comparison metrics can report
  per-language/document slices before changing defaults. The package fixture
  gate enforces minimum coverage for these slices so aggregate metrics cannot
  hide a missing TypeScript or Markdown driver.
- `bm25_metrics_baseline.json` - the checked-in exact BM25 baseline used by the
  package test-suite regression gate.

Keep new files that must not be chunked outside `corpus/`. The golden test
chunks every `.dart`, `.ts`, `.tsx`, `.md`, `.markdown`, and `.txt` file it
finds under the corpus root.

## samples/

`samples/` holds reusable, synthetic example inputs. `calculator.dart` and
`search.txt` were moved from `example/`; `use_calculator.ts` was extracted from
the code example's inline setup. The examples read these files directly and
leave them unchanged. `tables.md` exercises the boundary between literal table
syntax in a code fence and an actual Markdown table.

`test/fixtures_pipeline_golden_test.dart` checks both corpora. The goldens record
content, line ranges, type, metadata, and fixture-relative ids, including parent
heading references. `.gitattributes` preserves fixture LF line endings so hashes
survive Windows checkouts. The sample corpus also exercises text retrieval;
it does not alter the historical 65-query benchmark.

To refresh both snapshots after reviewing an intentional change, run from the
package directory:

```bash
UPDATE_GOLDENS=1 dart test test/fixtures_pipeline_golden_test.dart
```

## benchmarks/

`model_comparison_*` records the follow-up Arctic XS/S and BGE-small comparison,
including Q8/Q4 variants. It reuses `embedding_comparison/` unchanged. See the
[model comparison protocol and results](../../../docs/wayfinder_embeddings_model_comparison.md).

`local_metrics_baseline.json` records aggregate and per-group metrics for the
pinned native model after the storage cleanup. It carries model identity,
token policy, and candidate settings, without duplicating full ranked outputs.
Its recorded `modelName` is the identity string in force when the run happened;
dropping the download URL and license from model identity changed that string,
so a fresh run reports a different one. The gate compares metric drops only.
The native CI job compares its live BM25, dense, and hybrid runs against these
metrics. Model preparation is required for this gate. The regular deterministic
test suite continues to use the independent BM25 baseline in `corpus/`.
