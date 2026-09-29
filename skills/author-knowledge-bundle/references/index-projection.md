# Index projection

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply. Every affected `index.md` is rewritten as part of
the atomic bundle write, and nothing generates indexes for you — `wayfinder validate`
checks the result but does not produce it — so this reference is the complete
producer spec.

An index follows the OKF index format (OKF §8) exactly: no frontmatter, except
that the bundle-root `index.md` carries `okf_version`, which agrees with the
selected Profile binding (or legacy declaration). Every nonempty directory has an `index.md`, including every
area, sub-area, `references/`, and each nonempty subdirectory of `references/`.

Every index is the deterministic semantic projection of its directory —
immediate children only, omitting the index itself. Conformance compares the
parsed groups, membership, order, labels, targets, and descriptions; harmless
Markdown presentation differences do not affect it. An index never carries
authored ordering, directory descriptions, or other unique knowledge:
regenerating it must lose nothing.

## Groups

Present groups appear in this order; empty groups are omitted.

1. **`Bundle`** — root index only. In 2026.3 it contains `log.md` alone,
   with fixed label `Knowledge Log` and no description. Legacy 2026.2 also
   includes `profile.md`, `types.md`, and present `actors.md`, in that order,
   with concept titles and descriptions.
2. **Type groups** — every other concept, grouped under its exact `type` as the
   heading. Standard type groups follow the selected Profile manifest order (the legacy
   `types.md` order for 2026.2);
   registered project-specific type groups follow afterward in case-sensitive
   lexical order. An unregistered used type also sorts with the project types,
   so the projection stays reproducible while that separate registry defect is
   repaired.
3. **`Directories`** — immediate subdirectories. Each label is the final path
   segment exactly as written, each target is the relative directory path with a
   trailing slash, and directory entries carry no description.
4. **`Assets`** — immediate non-Markdown files, under `references/` and its
   descendants only. Each label is the filename exactly as written, each target
   is the relative file path, and asset entries carry no description.
   Non-Markdown files elsewhere are outside this projection.

Within a type group, entries sort by `title` and then target path, both
case-sensitive. Directory and asset entries sort by target path. Every target is
relative to the index containing it. Concept labels and descriptions are copied
verbatim — the Profile deliberately tightens OKF §8's SHOULD to a MUST here so
an index is mechanically checkable and safely regenerable without becoming a
second source of truth.

A target is a relative URL. When a filename carries a character a plain link
destination cannot — a space, a parenthesis, a character outside ASCII —
percent-encode it in the target (`%20`, `%28`, `%29`, UTF-8 escapes for
non-ASCII). Percent-encode `#` and `?` too (`%23`, `%3F`) even though a
destination can carry them raw — a URL splits at them into fragment and query —
and never write `%2F` for a slash: both raw-`#`/`?` and slash-escape spellings
are rejected. Conformance compares targets percent-decoded, so any valid
spelling matches. CommonMark's angle-bracket destination
(`<board deck (1).pdf>`) is accepted too — okf reads it as the same encoded
target — but the percent-encoded form is the canonical spelling okf's own
tooling writes. The label is not a URL and stays exactly as written; sorting
uses the decoded target path.

A complete 2026.3 root index covers the root log, every other root concept,
and every immediate directory. A 2026.2 root index also covers its required
Profile declaration and type registry, plus the actor registry when present.

## Examples

A root index:

```markdown
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
<!-- Legacy 2026.2 only: profile.md, types.md, and actors.md entries follow here. -->

# Analysis

* [Retention window](retention-window.md) - How long generated exports are kept before deletion.

# Directories

* [references](references/)
* [reporting](reporting/)
```

An area index uses the same projection. Exact registered type names are
headings:

```markdown
# Glossary Definition

* [Annotation](annotation.md) - A reviewer comment anchored to a region of a rendered report.
* [Export profile](export-profile.md) - The named settings bundle an export is rendered under.

# Business Rule

* [Annotations are immutable once exported](annotations-immutable-once-exported.md) - An exported annotation is never edited in place.

# Question

* [Annotation types in scope](annotation-types-in-scope.md) - Which annotation kinds must survive the PDF export.

# Request

* [Include PDF annotations in the export](include-pdf-annotations.md) - Client asks that reviewer annotations survive the PDF export.
```

A `references/` index lists assets; a verbatim filename that needs it is
percent-encoded in the target and exact in the label:

```markdown
# Assets

* [board deck (1).pdf](board%20deck%20%281%29.pdf)
* [notes.txt](notes.txt)
```
