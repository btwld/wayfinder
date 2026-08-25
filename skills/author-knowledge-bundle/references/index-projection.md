# Index projection

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply. Every affected `index.md` is rewritten as part of
the atomic bundle write, and nothing generates indexes for you — `okfp validate`
checks the result but does not produce it — so this reference is the complete
producer spec.

An index follows the OKF index format (OKF §8) exactly: no frontmatter, except
that the bundle-root `index.md` carries `okf_version`, which agrees with the
profile declaration. Every nonempty directory has an `index.md`, including every
area, sub-area, `references/`, and each nonempty subdirectory of `references/`.

Every index is the deterministic semantic projection of its directory —
immediate children only, omitting the index itself. Conformance compares the
parsed groups, membership, order, labels, targets, and descriptions; harmless
Markdown presentation differences do not affect it. An index never carries
authored ordering, directory descriptions, or other unique knowledge:
regenerating it must lose nothing.

## Groups

Present groups appear in this order; empty groups are omitted.

1. **`Bundle`** — root index only: `log.md`, `profile.md`, `types.md`, and
   `actors.md` when present, in that order. `log.md` has the fixed label
   `Knowledge Log` and no description; the other entries take their concept's
   `title` as label and copy its `description` exactly.
2. **Type groups** — every other concept, grouped under its exact `type` as the
   heading. Standard type groups follow the canonical `types.md` order;
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
non-ASCII). Conformance compares targets percent-decoded, so any valid spelling
matches, but prefer the fully percent-encoded one: it is the spelling every
layer of tooling accepts today. The label is not a URL and stays exactly as
written; sorting uses the decoded target path.

A complete root index therefore covers the root log, the two required
registry/declaration concepts, the conditional actor registry, every other root
concept, and every immediate directory.

## Examples

A root index:

```markdown
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
* [Concepta OKF Profile](profile.md) - Declares the Concepta profile and OKF versions this bundle follows.
* [Types](types.md) - The standard and project-specific types available to this bundle.
* [Actors](actors.md) - Actor IDs mapped to identity, affiliation, role, and active period.

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
