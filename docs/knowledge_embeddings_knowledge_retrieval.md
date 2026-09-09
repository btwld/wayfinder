# Knowledge retrieval: relevance, authority, and lifecycle

Reviewed 2026-09-09. These are implementation findings and recommendations,
not additional OKF fields or profile rules. The package now exposes a separate `okf_knowledge.dart` adapter. Its measured
component comparisons are in the [ablation report](knowledge_embeddings_ablation.md).

## Priorities and existing components

1. **Preserve knowledge context.** Use the existing `okf` parser and link
   resolver for concepts, provenance, lifecycle, and relationships. Preserve
   paths and line ranges for citations. In this repository, OKF governs the
   profile, which governs the implementation guide. Similarity cannot reverse
   that chain; it does not determine which conflicting assertion governs.
2. **Make updates and filtering correct.** Refresh metadata independently of
   vectors, remove obsolete chunks when replacing a source, separate model
   identities, and rebuild lexical snapshots after changes. Current guidance
   and historical explanation require different search scopes.
3. **Measure optional semantic retrieval.** Keep BM25 for identifiers and
   explicit terminology. Add the small encoder for paraphrases and inspect
   dense/hybrid failures by case. Neither similarity nor RRF establishes
   authority, truth, or answerability.
4. **Tune performance after correctness.** Use a larger judged knowledge corpus
   before changing models, HNSW settings, fusion weights, or native concurrency.

The [`okf` package](https://pub.dev/packages/okf), already used by `okf_profile`,
provides frontmatter parsing, lifecycle/trust accessors, bundle loading, and
link resolution. The adapter uses it directly instead of introducing another YAML or
relationship parser.

## Knowledge signals are not a single priority score

The pinned [OKF §5](../skills/author-knowledge-bundle/references/OKF-0.2.md)
governs these meanings; [profile §6](../profile/okf-profile.md) describes
Concepta's requirements for their use.

| Signal | Useful for | Does not establish |
| --- | --- | --- |
| Type, title, description, tags, path | Routing, explicit scope, readable context | A global authority order between concept types |
| `status` | Labeling drafts, separating current use from deprecated history; absent means stable in OKF | Verification, authority, or freshness |
| `stale_after` | Comparing freshness against the query's date | Whether a newer assertion is correct |
| `verified` | Deriving OKF's advisory trust tier and retaining verification events | That unverified concepts are unreadable |
| `sources` and actor registry | Following provenance and identifying whose assertion a claim represents | Equal authority for every human reviewer |
| `usage_count` and `usage_window` | Coarse adoption/liveness in context | A comparable popularity score across source kinds |
| Source links and relationships | Loading governing, supporting, conflicting, or successor context | That semantic neighbors are declared relationships |

Do not add a universal numeric priority field or store inferred credibility in
concepts. Consumer ranking choices belong outside bundle metadata. Retain the
underlying evidence and explain which source governs a conflict.

## ObjectBox review and fixes

Keep the split between `ChunkEntity` and `EmbeddingEntity`: text, location, and
metadata belong to a chunk; a vector identifies its chunk, provider, and
artifact/preprocessing identity. BM25 needs no vector entity. The fixed
384-dimensional cosine index matches the selected encoder. Other dimensions
need a separate generated schema.

ObjectBox recommends short explicit transactions for operations spanning
multiple reads/writes. Single writes now use the same batch transaction, and
deleting a chunk removes its vectors atomically. Inference and vector
conversion/validation stay outside the transaction. See
[ObjectBox transactions](https://docs.objectbox.io/transactions).

ObjectBox's unique `replace` strategy creates a different internal ID, which
can break incoming relations. Updates now preserve both entity IDs and assign
the relation by its stored target ID. A native reopen test checks IDs,
relations, and refreshed metadata. See
[unique constraints](https://docs.objectbox.io/entity-annotations#unique-constraints).

A new stress test stores 80 closer vectors from a previous model and one
active-model vector. Searching the active model returned nothing, even after
experimentally widening ANN candidates from 50 to all 81 records. When ANN
returns fewer usable hits than requested, the store now falls back to exact
cosine scoring within the selected source/model. The regression passes.
Fully populated ANN result sets remain approximate.

The fallback is linear in the selected model's vector count. Prefer one active
embedding space per database when integrating upgrades, and benchmark
selective queries at scale. JSON metadata is currently filtered in Dart, not
through native indexed fields. `ContentSearcher` also bounds metadata-filter
candidate expansion; highly selective filters can still underfill results.
The OKF adapter selects eligible concepts before scoring and reads their
vectors by chunk/source/model identity, using exact cosine scoring. It therefore
does not inherit the generic searcher's candidate-window limitation. This is
linear work over eligible vectors, not a demonstrated large-corpus ANN strategy.
See [ObjectBox vector search](https://docs.objectbox.io/on-device-vector-search).

Finite Dart doubles can become infinity or an all-zero vector as float32.
ObjectBox now rejects those vectors at storage/query boundaries before any
batch writes. Tests check that rejected batches preserve existing data.

## Embedding choice and lifecycle

Retain Arctic Embed XS Q8_0 through llamadart for the approximately 25 MB
model budget. It is a tested compact candidate, not a universal best model.
Its model card specifies 384 dimensions, CLS pooling, normalization, a
512-token context, and a retrieval query prefix distinct from passage text.
See the [Snowflake model card](https://huggingface.co/Snowflake/snowflake-arctic-embed-xs).

Open one engine per session, batch passages, and reuse unchanged vectors.
Metadata-only changes should not require inference. Encode a query once and
reuse its vector through candidate expansion/fusion. Artifact or preprocessing
changes need a distinct identity. Keep full source text when explicit
truncation is used.

The adapter compares body-only inputs with title, heading, and passage inputs
under separate preprocessing identities. It retains provenance as metadata,
without embedding the full YAML. `KnowledgeSnapshot.fitInputs` splits oversized
passages using the actual model tokenizer, counts context against the budget,
and preserves source text and citation spans. Inputs that cannot fit even one
word plus context fail before store mutation; nothing is silently truncated.

Keep conservative 512-token batch/microbatch settings until measured.
llamadart exposes batch sizes and parallel sequences for throughput tuning,
with memory tradeoffs. See its
[embedding guide](https://llamadart.leehack.com/docs/guides/embeddings).
Build/startup and memory measurements are in the
[local search report](knowledge_embeddings_local_search.md).

## New diagnostic cases

The [fixture](../packages/knowledge_embeddings/fixtures/knowledge_retrieval/cases.json)
has 13 synthetic chunks and 13 questions: 12 answerable and one unanswerable.
Judgments were written before running the model. Caller-projected metadata
and explicit scopes test retrieval boundaries; this is not a conformant
example bundle or a general authority resolver. The original 65-query corpus
and judgments remain unchanged.

Apple M2 Max; pinned model; top 3; 50 hybrid candidates. Memory and ObjectBox
produced the same judged results:

| Method | Relevant first result | Recall@3, answerable cases | Candidates for unanswerable question |
| --- | ---: | ---: | ---: |
| BM25 | 10/12 | 11/12 | 2 |
| Dense | 8/12 | 12/12 | 3 |
| Hybrid RRF | 10/12 | 11/12 | 3 |

These include caller-scoped cases and are diagnostic, not a representative
aggregate benchmark or a new promotion gate.

- **Exact symbol:** all methods retrieve `resetSessionToken` first.
- **Paraphrase:** dense retrieves the right recovery passage second; BM25 and
  hybrid miss it at top 3. Deprecated advice ranks first in dense. Weak lexical
  matches can bury a semantic-only hit during fusion.
- **Negation:** dense ranks retryable operations above the prohibition; BM25
  and hybrid put the prohibition first.
- **Authority:** all unscoped methods rank a contradictory implementation
  above its governing rule. Explicit governing scope corrects all three.
- **Freshness:** dense picks expired guidance despite stable status. Explicit
  current scope retrieves the current source for all methods.
- **Lifecycle and file scope:** current/history and server/browser filters
  retrieve the intended sources without leaking excluded candidates.
- **Missing trust:** unverified knowledge remains retrievable.
- **No answer:** every method returns candidates. Scores are not calibrated
  probabilities; verify supporting passages before answering.

The cleanup now preserves caller-supplied Markdown metadata on every block and
refreshes stored metadata without re-encoding unchanged text. Lexical indexes
are snapshots and require rebuilding after updates. Generic `IngestionPipeline` remains append/dedupe. `KnowledgeIndex.synchronize`
adds atomic bundle replacement: it removes obsolete chunks and all their vectors,
refreshes metadata/citations without unnecessary inference, and rebuilds its
lexical snapshot after commit. Other bundles in a shared store are preserved. Reusing a stored explicit ID for
different text with deduplication enabled now fails rather than pairing new
text with an old vector.

Run from `packages/knowledge_embeddings`:

```bash
# No model needed:
dart run tool/evaluate_knowledge_cases.dart comparison_results/knowledge-bm25.json
# Prepared model and installed ObjectBox library required:
dart run tool/evaluate_knowledge_cases.dart comparison_results/knowledge-native.json --native
```

JSON records each case's rankings, scores, top-one relevance, recall, and
unanswerable candidate count. CI uploads this report alongside the existing
full-corpus gate. Tests also cover metadata updates, preserved relations,
model isolation, invalid float32 writes, and deletion across models.
