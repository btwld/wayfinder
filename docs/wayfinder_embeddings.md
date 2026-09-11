# Knowledge retrieval: implementation and evidence

Start with [ADR-0009](adr/0009-local-knowledge-retrieval.md) for the accepted
model choice: Arctic Embed XS Q8_0 through llamadart, with verified local
weights and optional ObjectBox persistence. The reusable OKF adapter retains
BM25 as its default and exposes semantic and hybrid retrieval explicitly.
Application command defaults are a separate decision.

## Implementation

- [Package guide](../packages/wayfinder_embeddings/README.md): APIs, supported
  command-line entry points, fixtures and native setup.
- [Evaluation runbook](wayfinder_embeddings_eval.md): deterministic gates,
  native checks and commands to reproduce comparisons.
- [Local implementation report](wayfinder_embeddings_local_search.md): model
  delivery, native build hooks, schema migration and initial measurements.

Document embeddings are generated when a caller synchronizes a knowledge
snapshot with an encoder. ObjectBox saves passages and vectors; compatible
unchanged inputs reuse their vectors. Semantic search generates query vectors
in memory. Preparing or packaging a model does not index a knowledge bundle,
and `okfp validate` does not use embeddings.

[Wayfinder](../packages/wayfinder_cli/README.md) exposes `validate`, `index` and
`search`. It persists complete snapshots and document vectors, then opens them
for semantic searches without document inference. Its application choice is
recorded in [ADR-0010](adr/0010-station-cli.md). The historical saved-vector
benchmarks below reload sources and synchronize again; they do not measure
Wayfinder's saved-snapshot opening path. `okfp` continues to expose validation.

## Which experiment answers which question?

| Evidence | Question | Scope and limits |
| --- | --- | --- |
| [Initial implementation](wayfinder_embeddings_local_search.md) | Does the local provider work, and what does storage cost? | 65 queries over mixed code/text; generic ObjectBox search uses HNSW |
| [Knowledge diagnostics](wayfinder_embeddings_knowledge_retrieval.md) | How do scope, lifecycle, authority and negation affect lookup? | 13 caller-projected cases; diagnoses failures without defining OKF rules |
| [OKF component experiment](wayfinder_embeddings_ablation.md) | What do headings, lifecycle and explicit relationship policies contribute? | 35 questions parsed through OKF; exact eligible-vector scoring |
| [Retrieval comparison](wayfinder_embeddings_comparison.md) | What do keyword, BM25, embeddings and hybrid cost and recover? | 160 synthetic questions split by topic; isolated processes and separate storage scale test |
| [Model comparison](wayfinder_embeddings_model_comparison.md) | Does a different small model improve on XS? | Five artifacts on the same previously inspected fixture; exploratory comparison |

The [executed benchmark plan](wayfinder_embeddings_benchmark_plan.md) records
the protocol, and the [fixture guide](../packages/wayfinder_embeddings/fixtures/README.md)
locates frozen judgments, summaries, raw reports and provenance. Keep historical
judgments and results intact; new relevance reviews belong in a separately
identified evaluation.

## Conclusions and limits

XS and the larger Q8 alternatives each returned the expected first assembled
context for 50 of 60 answerable test questions. XS had the lower measured query
cost and smaller artifact. This supports keeping XS; it does not establish
universal superiority or equivalence between models.

The four-arm comparison returned 46/60 correct first contexts for keyword,
45/60 for BM25, 50/60 for XS embeddings and 46/60 for hybrid. Context assembly
includes explicit consumer policy, so these scores are not pure model ranking
or generated-answer accuracy. Every arm returned candidates for all 20
unsupported questions. No client corpus was evaluated.

ObjectBox provides persistence and atomic writes. The OKF adapter scores all
eligible vectors exactly in Dart, unlike the generic store's HNSW path. Its
large-corpus cost must be measured independently of small-fixture relevance.
Use the later repeated-process reports for current startup/query comparisons;
the initial report retains earlier first-use observations with their limits.

Next experiments are passage selection, independently reviewed supporting
judgments, answerability and exact-versus-approximate storage retrieval. Their
acceptance criteria and rationale are owned by ADR-0009.
