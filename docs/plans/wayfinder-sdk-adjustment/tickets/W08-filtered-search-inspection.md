# W08 — Expose filtered search and bounded index inspection

**Batch:** workbench
**Status:** planned
**Blocked by:** W03

## What to build

A direct Dart consumer can search a completed Wayfinder index by concept type and path, then inspect the matching passage and index configuration through public SDK operations. Existing CLI/MCP calls keep their behavior.

## Scope

Reuse the extracted runtime and KnowledgeIndex policy. Add a separate AckInfer-owned request contract for the new SDK surface; preserve the existing search request and wire schema. Default to the same dense mode, contextual input, relationship expansion, and limit as Wayfinder. Support concept-type and path-prefix eligibility before ranking and limiting. Expose bounded read-only status, available types, and passage details from the same completed generation. Keep optional BM25/hybrid access explicit rather than a silent fallback.

Use existing upstream values where possible. Generation identity, compatible-vector counts, model state, source revision, and effective embedding input must be evidenced or marked unavailable. Apply existing locking and freshness rules; do not bypass private storage from a consumer. If later lifecycle work already exists, use it instead of a competing implementation.

Record the effective applied filter policy with its result identity. Use OR within one category and AND between categories; empty selection means no restriction in that category. Facets and passage pages must identify their corpus, generation, and completeness. Related context must follow the effective eligibility policy or disclose a separately authorized context-policy exception. Tags and Git-state filtering are not silently added to the existing search contract.

## Acceptance criteria

- [ ] Default calls retain CLI/MCP names, schema, results, errors, and lifecycle behavior on the characterized fixture.
- [ ] Generated request parsing and direct construction both reach validation; unknown concept types remain strings rather than a closed enum.
- [ ] Type and path eligibility run before ranking/top-k; a typed match beyond the unfiltered top-five is found.
- [ ] Empty filters include all eligible concepts; lifecycle defaults are unchanged and current-only options require an explicit as-of instant.
- [ ] OR-within/AND-between semantics, effective policy identity, and selected-source revision are demonstrated by contract tests.
- [ ] Matches, selected context, reasons, notices, and mode-specific scores retain their meanings; restricted context is not silently restored by expansion.
- [ ] Bounded inspection uses a single identified completed generation, exact citations, and truthful model/vector/input availability; no invented timestamp, count, or effective input.
- [ ] Type counts, if exposed, count distinct concepts in the labeled corpus and not result chunks; returned matches and top-k limits are not total corpus matches.
- [ ] Optional chunk-kind inspection filters operate on the correct bounded public snapshot view, disclose pagination/completeness, and do not alter the normal one-best-passage-per-concept search contract.
- [ ] No source writes, unlocked independent database reads, duplicated search engine, or CLI-private imports are introduced.
- [ ] A direct public-import consumer plus real generation and targeted regression tests demonstrate the behavior. Native gaps remain reported.

## Out of scope and external gates

Not part of W01–W03. No concurrent-refresh fix, source authoring, model replacement, vector visualization, cross-encoder service, or package release. Actual native model/store setup gates semantic evidence. Optional comparisons do not block the minimum filtered dense workflow. Preserve busy/stale refusal until its owning ticket changes it. A Git badge is not changed-only retrieval; such a future search requires an exact pre-ranking path-set contract and a separate revision identity.

## Test and demonstration evidence

Use a small synthetic or authorized multi-type bundle with duplicate passages, an unknown type, a changed/deleted file, and a missing-model case. Run before/after default contract cases and the filter-before-limit case. Include combined filters, empty selections, related-context exclusions, known versus unavailable counts, and partial inspection pages. Inspect one passage and configuration through a public consumer. Record snapshot, toolchain, generated-file stability, checks, failures, and skips.

## Review and handoff

Review Standards and Spec separately at fixed base/head. Confirm shared ownership and no wire drift. This ticket supplies WB02; it does not authorize that ticket's execution automatically. Detailed requirements and source evidence are in [WORKBENCH.md](../WORKBENCH.md) and [FILTERS_AND_DIFFS.md](../FILTERS_AND_DIFFS.md).
