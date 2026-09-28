# X02 — Extract source material into a reviewed capture workflow

**Batch:** optional  
**Status:** deferred  
**Blocked by:** F01, W07  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A real desktop and CLI/agent import workflow preserves original evidence, extracts located text, and promotes only explicitly reviewed changes into knowledge.

## Scope

- Resolve ADR-0013 proposal details and choose the first actual format/consumer before implementation.
- Retain hashes, media type, extractor identity/version, locations where available, warnings, and sensitivity policy.
- Keep capture storage and indexing opt-in; use generated contracts for import control records only.

## Acceptance criteria

- [ ] Original evidence remains immutable and traceable; repeated input is recognized by content identity.
- [ ] Extraction failures, password protection, unsupported formats, and missing locations are reported honestly.
- [ ] No raw capture enters ordinary knowledge search by default or receives automatic verified status.
- [ ] Promotion uses reviewed structured changes with provenance and refuses unreviewed overwrite.
- [ ] A captures directory is not mislabeled as an OKF bundle; a separate collection or explicit valid projection is used.
- [ ] A public capture package is introduced only when both real consumers share the proven interface.

## Out of scope and external gates

Activation gate: a concrete shared import workflow. Do not add speculative PDF/DOCX/network dependencies now.

## Test and demonstration evidence

Use synthetic assets and review/commit fixtures; privacy and provenance assertions are part of correctness.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
