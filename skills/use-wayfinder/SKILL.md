---
name: use-wayfinder
description: Find and verify recorded project knowledge with Wayfinder semantic search, or index, validate, and inspect an OKF bundle. Use when questions depend on recorded decisions, requirements, ownership, or rationale. Use direct reads for known paths and enumeration for exact counts.
---

# Using Wayfinder

Wayfinder returns cited passages from local OKF bundles, not generated answers.
Search discovers evidence; project authority rules determine what governs.
Follow the project's bundle layout and setup restrictions.

## 1. Discover

For unknown locations or paraphrased questions, prefer available Wayfinder MCP
search before broad listings. Use one focused question or exact known ID;
reformulate only for a missing angle. Honor explicit Wayfinder-discovery requests.
MCP searches configured bundles unless launched for one; evidence folders may be
separate bundles. Follow source links for history/provenance.

Without MCP, use the CLI:

```sh
wayfinder search "<focused question>" --limit 5
wayfinder search knowledge "<focused question>" --limit 5
```

An explicit path selects one bundle; otherwise project configuration selects them.
Search needs the local embedding model. There is no model-free fallback. Omit
retired CLI `--mode` and MCP `mode` fields.

For a known file, read directly. For an exact metadata list or count, use MCP `query` (inline query or saved ID) or `wayfinder query --type <type> --output json`; it reads live concepts without a model/index. Check totals and `has_more`, page through results, and keep counts of whole concepts distinct from records embedded in their bodies. Saved definitions live in the consuming project’s `.wayfinder/queries/`; they do not execute computations or establish attestation. See the runtime [query guide](https://github.com/btwld/wayfinder/blob/main/docs/queries.md). Semantic top-k cannot
prove completeness or absence. Targeted filename/keyword lookup is also useful
after discovery. A model or index failure is not evidence that a fact is missing.

## 2. Read the evidence

Open complete relevant sections, including exceptions. Batch independent reads
and follow sources/relationships within the authorized corpus; unresolved graph
links do not prove absence. Results group matches/context with path:line citations,
metadata and source links. Use CLI `--output=json` for programmatic selection.
Read known sources directly when excerpts omit context; do not keep increasing
search limits. Preserve relevant governing context even when linked hits are weak.

## 3. Verify and answer

For current-state claims, check owning status fields, decisions, open items, and
relevant superseding evidence. Summaries can lag their owning pages. Report a
conflict rather than silently selecting one excerpt. `stable` is document
lifecycle, not approval. Similarity and links do not establish authority.
Keep evidence, decisions, and executed validation distinct.

Cite verified project-relative paths and line ranges. Stop when the requested
claims and relevant authority checks are supported. Before calling something
undocumented, inspect its owning source and use a targeted lookup if needed.
State remaining gaps without inventing facts.

## Operations and boundaries

- For missing, stale, or incompatible indexes, refresh the same selected bundles
  and retry. Do not rebuild a working index or use `--force` routinely.
- A `refresh-in-progress` notice means an index is running and the results come
  from the previous one. Reread passages marked `source changed` in their files
  before citing them.
- Navigation/history files such as `index.md` and `log.md` are not indexed
  passages. Read them directly. Search does not read binary payloads.
- For setup, index, validate, graph, or runtime failures, read the relevant
  [operations](references/operations.md) section. Do not install hooks or change
  setup merely to answer a working search.
- Validation proves structural conformance, not business correctness. Before
  writing a bundle, use [author-knowledge-bundle](../author-knowledge-bundle/SKILL.md).
  For a whole-bundle review, use [assess-knowledge-bundle](../assess-knowledge-bundle/SKILL.md).
