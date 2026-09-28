# F02 — Add bounded Super Editor visual editing

**Batch:** C  
**Status:** planned  
**Blocked by:** F01  
**Baseline:** `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f` (verify the actual parent before implementation)

## What to build

A user edits supported Markdown visually, switches safely to source mode, saves, and reopens while unsupported material remains available without silent simplification.

## Scope

- Integrate Super Editor inside the editor module only, retaining one active editable representation.
- Start with a tested block subset and checkpoints on conversion; add blocks only with load/edit/save tests.
- Keep frontmatter outside the visual body model; source mode owns the full file while active.

## Acceptance criteria

- [ ] Paragraph/heading/inline-link edits round-trip through real files with metadata intact.
- [ ] Unsupported tables, footnotes, reference links, or extensions fall back to source mode rather than disappear.
- [ ] Mode switching alone never writes; undo/selection and conversion checkpoint policies are explicit.
- [ ] Keyboard navigation, clipboard, cross-block selection, input methods, and accessible controls are tested on the target platform.
- [ ] A failed conversion retains the original and current work; normalized formatting requires a visible diff policy.

## Out of scope and external gates

Do not add database blocks, collaboration, arbitrary plug-ins, or use search chunks as the editing model.

## Test and demonstration evidence

Use byte/diff fixtures plus Flutter interaction tests and manual IME/platform evidence. State untested platforms explicitly.

## Review and handoff

Read the canonical adjustment specification and repository instructions. Review Standards and Spec separately at a fixed base/head. Record commands, failures, skips, and unverified platforms. Do not merge, publish, close existing issues, or broaden scope. Mark done only when every acceptance item has evidence; otherwise identify the blocked item and preserve completed work.
