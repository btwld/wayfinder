# ADR-0009: Keep Arctic XS for local knowledge embeddings

- Status: accepted
- Date: 2026-09-09
- Scope: `knowledge_embeddings` tooling; no bundle or profile rule changes

## Context

The embedding implementation needs a small local model, predictable preparation
and indexing, and evidence that semantic retrieval helps knowledge lookup.
The [retrieval comparison](../knowledge_embeddings_comparison.md) tested
keyword, BM25, dense and hybrid retrieval. The subsequent
[model comparison](../knowledge_embeddings_model_comparison.md) tested Arctic
XS Q8, Arctic S Q8/Q4 and BGE-small Q8/Q4 against identical passages and judgments.

On the 60 answerable test questions, XS and both larger Q8 models returned the
expected first context in 50 cases. XS had the highest recall@10 and lower
query latency and artifact size. Alternatives fixed some questions and lost
others; paired uncertainty did not establish a first-context improvement.
Q4 was slower on the measured CPU/runtime. These are synthetic, previously
inspected test partitions, not independent real-corpus evidence.

## Decision

- Keep **Arctic Embed XS Q8_0** as the local embedding model, through in-process
  **llamadart**. Retain the revision, byte count, SHA-256 and preprocessing
  contract pinned in
  [`localEmbeddingModel`](../../packages/knowledge_embeddings/lib/src/embedding/embedding_model_spec.dart):
  25,279,840 bytes, 384 dimensions, CLS pooling, normalized vectors, a 512-token
  context and a query-only retrieval prefix. Runtime inference requires a
  verified local artifact; preparation owns downloading and caching.
- Keep **BM25 as the adapter's default** and dense/hybrid retrieval opt-in.
  Selecting an embedding model does not promote semantic retrieval to the
  default. Preserve keyword matching as a diagnostic control in evaluation.
- Keep **ObjectBox optional for persistence**. Its current OKF retrieval path
  scores eligible vectors exactly; its existence is not evidence of improved
  relevance or scalable approximate retrieval.
- Keep the Q4 and larger-model candidates in reproducible benchmark tooling.
  They do not become application assets or automatic model choices. Ollama
  remains removed; Gemma was excluded from this comparison.
- Preserve model/input identities, citation spans, explicit consumer policy,
  atomic updates and vector reuse. Similarity does not determine authority,
  freshness, correctness or whether a question has an answer. Identity covers
  the artifact bytes and preprocessing contract; the download URL and license
  are provenance, so re-mirroring verified weights reuses stored vectors.
- **Exclude footnote definitions from OKF passages.** OKF 0.2 §5.1 resolves
  per-claim attribution through `sources`, not footnote prose, and a short
  definition line otherwise competes with the body text it cites: the measured
  case was a dense query whose top match was
  `[^demo-0730]: Reporting demo transcript, 30 July 2026`. Markdown chunking
  keeps the definitions as a `footnote` chunk type for non-OKF corpora, where
  `SearchOptions.chunkTypes` selects them. A concept body made only of headings
  and footnotes keeps both, so nothing becomes unsearchable.

The detailed measurements, limitations, artifact hashes and raw cited results
live in the linked reports. This ADR records the accepted choice; it does not
turn benchmark outcomes into OKF or Concepta bundle conventions.

## Findings that guide the next experiments

1. **Passage selection is the first quality experiment.** The adapter keeps one
   best passage per concept. In observed failures, an unrelated section or a
   link-only passage survives while the supporting paragraph is discarded.
   Compare that baseline with two or three distinct passages per concept and
   bounded adjacent-paragraph context. Keep the same total context-token
   budget, source filters and citations; report raw ranking and assembled
   context separately. A plausible fix still needs measurement.
2. **Judgments need independent review.** A positive instruction to reuse a key
   can answer a question about rejecting a different key, but the frozen
   judgment credits only the explicit prohibition. Preserve the historical
   fixture. Add reviewed alternate supports in a separately identified
   evaluation, with fresh questions before further tuning. Inspect negation,
   exact identifiers, conflicting guidance and follow-up questions separately.
3. **Answerability is a separate problem.** Every arm returned candidates for
   unsupported questions. Evaluate abstention using development-calibrated
   criteria and report both unsupported-query false positives and missed
   answerable questions. Do not adopt an arbitrary cosine threshold or describe
   a ranked candidate as a supported answer.
4. **Storage optimization needs an exact reference.** At 50,000 synthetic
   vectors the current ObjectBox exact path was much slower than memory.
   Benchmark allocation/transfer improvements or selective ANN against exact
   eligible-vector results, including restrictive scope and model filters.
   Preserve update correctness and measure recall as well as latency.

The current one-engine lifecycle, batched passage encoding, query cache and
metadata-only vector reuse already work. Replacing the model or increasing
concurrency is not the first response to the observed passage-selection errors.

## CLI boundary

`okfp` currently exposes `validate` for bundle conformance checks. It does not
expose embedding preparation, indexing or interactive search. Existing local
commands and their working directories are documented in the package's
[command-line guide](../../packages/knowledge_embeddings/README.md#command-line-entry-points).

The package has a library API, a fixture search example, model preparation/build
tools and evaluation executables. A general command accepting a bundle path
and an arbitrary query is a follow-up interface decision; it is not supplied
by the fixed-query example or by `okfp validate`. Keep the validator's existing
dependency and conformance contract intact when designing that interface.

## Consequences and reopening

The selected artifact is already pinned; accepting this decision requires no
model change or re-embedding of indexes produced by the current implementation.
Databases from the removed provider/schema still need a fresh directory and
reindexing as documented in the [local implementation report](../knowledge_embeddings_local_search.md).

Excluding footnote definitions trades recall for precision: prose that exists
only inside a definition, beyond the `sources` entry it keys, is no longer a
retrievable passage. Reopen that choice if judged queries show such prose is the
best available support; filtering `footnote` at the policy layer instead of at
load time would keep it retrievable.

Reopen model selection when independently reviewed corpus results demonstrate
a useful quality gain within an explicit download, startup, query-latency and
memory budget, or when runtime compatibility requires a change. Record the
paired regressions and repeat the storage/cache checks. An upstream leaderboard
score or a smaller quantization alone is insufficient evidence to replace this
choice. Supersede this ADR when a new choice is accepted.
