---
name: use-wayfinder
description: Find and verify recorded project knowledge with Wayfinder semantic search, or index, validate, and inspect an OKF bundle. Use when questions depend on recorded decisions, requirements, ownership, or rationale. Use direct reads for known paths and enumeration for exact counts.
---

# Using Wayfinder

Wayfinder returns cited passages from local OKF bundles, not generated answers.
Search discovers evidence; project authority rules determine what governs.
Follow the project's bundle layout and setup restrictions.

## 1. Discover

For an unknown location or paraphrased question, prefer the available **Wayfinder
MCP search** before broad file listings. Ask one focused natural-language question.
Use exact IDs when known. Reformulate for a missing angle, not to repeat successful
discovery. If the user requires Wayfinder discovery, perform it explicitly.

MCP searches all configured project bundles unless its launch selects one bundle.
Do not assume an evidence folder is unindexed; it can be a separate bundle.
Follow source links or search that bundle when provenance or history is needed.

Without MCP, use the CLI:

```sh
wayfinder search "<focused question>" --limit 5
wayfinder search knowledge "<focused question>" --limit 5
```

An explicit path selects one bundle; otherwise project configuration selects them.
Search needs the local embedding model. There is no model-free fallback. Omit
retired CLI `--mode` and MCP `mode` fields.

For a known file or exact count, read or enumerate directly. Semantic top-k cannot
prove completeness or absence. Targeted filename/keyword lookup is also useful
after discovery. A model or index failure is not evidence that a fact is missing.

## 2. Read the evidence

Open returned paths and read the complete relevant sections, including exceptions.
Reuse resolved paths and batch independent reads. Follow source and relationship
links within the authorized corpus; an unresolved graph link does not prove that
its source is absent.

Results include ranked `matches` and bounded `context`. Project results include
`bundlePath`; combine it with `chunk.sourcePath` for a project-relative citation.
Inspect direct matches when linked context is unhelpful. Do not discard relevant
governing context. Use CLI `--output=json` for programmatic selection.

When excerpts omit needed context, read the source directly. Do not keep
increasing search limits instead of reading a known source.

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
- Navigation/history files such as `index.md` and `log.md` are not indexed
  passages. Read them directly. Search does not read binary payloads.
- For setup, index, validate, graph, or runtime failures, read the relevant
  [operations](references/operations.md) section. Do not install hooks or change
  setup merely to answer a working search.
- Validation proves structural conformance, not business correctness. Before
  writing a bundle, use [author-knowledge-bundle](../author-knowledge-bundle/SKILL.md).
  For a whole-bundle review, use [assess-knowledge-bundle](../assess-knowledge-bundle/SKILL.md).
