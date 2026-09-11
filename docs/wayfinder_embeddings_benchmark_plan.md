# Plan: measure the value and cost of local embeddings

Status: executed 2026-09-09; see the [measured report](wayfinder_embeddings_comparison.md). This plan does not change retrieval
defaults or OKF/profile semantics. Existing measurements are in the
[component report](wayfinder_embeddings_ablation.md).

## Question and comparison arms

Does a local embedding model recover useful knowledge that model-free search
misses, and is that improvement worth its startup, memory, indexing, and query
costs?

BM25 already works without embeddings: it ranks text using term statistics.
ObjectBox is a storage choice, not an alternative ranking algorithm.

| Arm | Retrieval | Model loaded | Purpose |
| --- | --- | --- | --- |
| Basic keyword search | Count distinct query terms found in each passage | No | Establish what simple text matching achieves |
| BM25 | Existing lexical index | No | Main production baseline without embeddings |
| Local dense | Existing Arctic Embed XS via llamadart | Yes | Isolate semantic retrieval |
| Hybrid | Existing BM25 + dense RRF | Yes | Test whether combining them improves results |

The basic baseline will use the same text tokenizer, count each matched query
term once, omit zero-match passages, and break ties by path and source position.
It will have no IDF, frequency weighting, or length normalization. Freeze this
rule before measuring it. It is a diagnostic baseline, not a proposed replacement.

A completely disabled retriever returns no passages and trivially has zero
retrieval recall. It is not a useful fifth search arm. Comparing an answering
LLM with no retrieved context would be a separate answer-quality experiment;
no answering model is introduced by this plan.

## What existing evidence does and does not establish

On 16 answerable held-out questions with the same selected OKF policy, BM25
returned correct first context in 14 cases, dense in 15, and hybrid in 14.
Support recall at three passages was 15/16, 16/16, and 15/16 respectively.
Memory and ObjectBox agreed. Every mode returned candidates on the no-answer
case, and one dense first result regressed relative to its body-only version.

This establishes a small synthetic quality comparison. It does not establish
that embeddings are worth their operating costs. The native evaluator currently
opens the model and builds vectors even for BM25 rows, and warm-query timings
reuse cached query vectors. Those rows cannot measure genuinely model-free
startup/indexing or the latency of a new semantic query.

## Fair quality comparison

1. Preserve the original 65-query corpus and the existing 35 OKF questions as
   regression sets. The old held-out questions have now been inspected; they
   must not be described as an untouched test set for future tuning.
2. Author a new generic, synthetic set before running retrieval: target at least
   120 questions across exact identifiers, terminology, paraphrases, negation,
   competing guidance, stale/current/history intent, section context, declared
   links, and at least 20 genuinely unanswerable questions. Keep near-duplicate
   questions and topics together when splitting development and test sets.
   Record answerability and supporting passage spans without model rankings.
3. Freeze a manifest with corpus/query hashes, development/test assignments,
   model identity, tokenizer, candidate count, and policy. Tune on development
   only; run the new test split after choosing settings. If later tuned against
   it, retire its held-out label.
4. Compare all four arms with identical eligible concepts, title/heading input,
   passage boundaries, top-k, context budget, date, and governing/link policy.
   Prepare a shared passage manifest outside measured runs so the model-free
   arm does not load a tokenizer model just to reproduce boundaries. Separately
   report normal end-to-end ingestion, including any tokenization costs.
5. Score raw ranked matches and assembled context separately. Otherwise a
   governing-source insertion could be mistaken for better semantic ranking.
   Preserve the existing one-best-passage-per-concept rule for the primary
   adapter comparison and label passage-level diagnostics separately.
6. Record first-result correctness, support recall@3 and @10, MRR, and per-case
   wins/losses. Report paired differences and bootstrap confidence intervals
   grouped by topic, plus absolute case counts. Do not interpret the small
   existing set as precise evidence of a population-level gain.
7. For unanswerable cases, report how many candidates each arm returns. Do not
   interpret similarity as confidence. If testing abstention later, calibrate
   thresholds on development only and report false abstentions and unsupported
   returns separately on the test set.

## Performance comparison

Use an isolated child process and fresh store for each arm. BM25/basic runs
must create zero document/query vectors and never open an embedding model;
verify counters rather than inferring this from the selected mode. Use compiled
CLI runs for headline measurements, recording SDK, platform, model checksum,
threads, corpus size, cache state, and commit/worktree identity.

Measure these phases separately:

| Scenario | Measurements |
| --- | --- |
| First setup/build | Download bytes/time, native setup, compile time, artifact size |
| Cached rebuild | Same inputs and populated caches; elapsed time and downloaded bytes |
| Fresh process, new index | Store/model open, parsing, splitting, embedding, writes, time to first usable result |
| Fresh process, existing index | Reopen, lexical reconstruction, vector reuse, first query |
| Warm process, uncached query | Query encoding, retrieval, context assembly, total latency |
| Warm process, repeated query | Same phases with query-cache hits labeled |
| Metadata-only update | Changed rows, encoding count (expected zero), elapsed time |
| Body edit/delete | Re-encoded chunks, obsolete rows removed, elapsed time, unaffected vectors reused |

Record p50/p95, peak resident memory, database bytes, model/native artifact bytes,
and document/query throughput. Use at least ten independent process starts;
for warm queries use randomized fixed-seed order, two warmup passes, and enough
measured passes for at least 1,000 queries. Rotate arm order. Report distributions
and run counts; stop and flag disk pressure or other substantial interference.
Fresh process does not mean cold filesystem cache; do not conflate them.

The current package may still run native build hooks for a BM25 entrypoint due
to its dependency graph. Report that shipped build footprint honestly. A future
separate lexical-only package/build would be an additional packaging experiment,
not a saving we can claim just because the runtime does not open the model.
Use task-owned cache directories for clean-build measurements; do not clear the
user's global caches.

## Storage and scale

Run the four arms against both stores at the existing fixture size. Then measure
1k and 10k passages; expand to 50k only if resource use permits. Use generated
unique generic distractors with recorded seeds for performance stress, and
label them as scale fixtures rather than evidence of broader semantic quality.

Keep store measurements separate from inference using precomputed vectors.
ObjectBox's persistence and transaction behavior are distinct from retrieval
quality. Compare the adapter's exact eligible-vector scoring consistently across
stores. Benchmark ANN separately against exact top-k if approximate search is
considered; report recall loss, selective-filter misses, and latency together.

## Implementation order and deliverables

1. Extend the evaluator with isolated arms, explicit cache scenarios, phase
   timings, and counters. Reuse existing metrics/judgments and store tooling;
   add the simple keyword baseline only in evaluation code.
2. Add the frozen new questions and manifest, then run existing regression sets
   to verify identical eligibility and citation handling across arms.
3. Run development, select settings, and run the new untouched test split.
4. Run compiled startup/query/update benchmarks and the separate storage scale
   sweep. Keep long benchmarks manual; CI runs correctness and small smoke cases.
5. Commit a compact report with per-query changes, latency/memory/size tables,
   commands, hashes, and raw JSON artifacts. Preserve failures and regressions.

Until then, retain BM25 as default and local embeddings as opt-in. Recommend a
default change only if the new test set shows a convincing paired quality gain,
no loss on required identifier/negation/scope cases, and acceptable measured
latency/memory/startup costs. Product-specific cost limits have not been set;
report the tradeoff instead of inventing a universal acceptable threshold.
