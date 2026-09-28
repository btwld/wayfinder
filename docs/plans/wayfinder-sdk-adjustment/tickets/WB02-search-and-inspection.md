# WB02 — Search by concept type and inspect passages in the workbench

**Batch:** workbench
**Status:** planned
**Blocked by:** WB01, W08

## What to build

A person points the workbench at a bundle, explicitly refreshes its search index, searches using Wayfinder, filters by concept type, and opens the matched passage with its source and embedding details. This completes the first workbench without requiring visual editing.

## Scope

Connect the real public SDK to the existing shell's Search and Index destinations. Keep dense Wayfinder semantic search as the default, with a controlled query, explicit submit, concept-type/path filters, and preserved selection state. Keep Matches, Related context, and Notices separate. Add bounded passage/index inspection and local redacted diagnostic export. Surface native/model, stale, busy, and source-change conditions honestly. Keep Library and Validation usable while retrieval is unavailable or busy.

Treat concept type, chunk type, and content type as different values. Use snapshot-owned metadata and counts. No result-top-k filtering in the UI. Optional mode comparison may follow once the normal search workflow passes; it uses the same library/corpus and does not assert a quality winner.

## Acceptance criteria

- [ ] A real completed index produces dense search hits; selecting one opens its cited source or warns about a changed/deleted source.
- [ ] Type/path filtering uses the public pre-ranking policy and reaches a relevant typed concept outside an unfiltered result window.
- [ ] Custom types remain selectable; concept and chunk type are labeled separately; any counts are snapshot-scoped distinct concepts.
- [ ] Results preserve mode, rank, source lines, context reasons, notices, and query/filter state; scores are not confidence percentages.
- [ ] Index view reports actual generation/configuration, native/model state, and available passage/vector diagnostics without reading storage files directly.
- [ ] Effective input is shown only when exactly available; token-fitting warnings remain visible and no vector plot or invented progress is required.
- [ ] Index refresh changes only derived data. Opening/searching never silently downloads models, regenerates navigation files, or rebuilds the index.
- [ ] Missing assets, stale index, failed refresh, and busy state remain distinct when the SDK can establish them; no silent keyword fallback or lock bypass occurs.
- [ ] Folder/query changes reject obsolete completions without falsely claiming native cancellation; the UI remains responsive on the tested backend.
- [ ] Source-tree non-mutation, keyboard/narrow-window operation, diagnostic redaction, and app/SDK default-result parity are demonstrated.

## Out of scope and external gates

Depends on the public SDK work and verified native assets, not F02/Super Editor, W06 concurrent refresh, or W07 Profile writes. Missing native evidence blocks semantic completion but not honest partial delivery. No new search engine, LLM answering, reranker service, vector visualization, or app store release. Do not execute this automatically after Batch A.

## Test and demonstration evidence

Show open → index → query → type filter → inspect → source on a synthetic or authorized bundle. Include unavailable model, corrupt/mismatched configuration, failed index, stale/busy response, changed/deleted source, duplicate chunks, custom types, and late request results. Record snapshot, mode, package/toolchain versions, checks, skips, and actual native target. An optional mode comparison needs identical inputs and separate score labels; relevance claims additionally need fixed judgments.

## Review and handoff

Review Standards and Spec separately; distinguish self-review from independent review. Preserve validated search behavior for later F03 editing integration. Requirements and sources: [WORKBENCH.md](../WORKBENCH.md).
