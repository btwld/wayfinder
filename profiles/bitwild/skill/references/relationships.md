# Relationships and execution records

A relationship gives one link a stable, typed meaning, read from the
containing concept outward. Write it in the frontmatter key `relationships`:
a list of mappings, each with exactly `relationship` (a declared name) and
`resource` (the target). A `# Relationships` body heading types nothing, and
validation does not read it.

```yaml
relationships:
  - relationship: superseded-by
    resource: /reporting/new-term.md
  - relationship: implemented-by
    resource: https://github.com/org/repo/pull/42
```

`resource` is a bundle path starting `/` or a URL, never a scope descriptor.
`sources` records derivation/credibility, not typed relationships.

## Standard names

The Profile package declares these names. Declare a project name in the
`wayfinder.json` entry's `relationships`, with a description that truthfully
defines it once. Never invent a name in a concept.

| Name | Meaning |
| --- | --- |
| `superseded-by` | This concept has been replaced by the target |
| `depends-on` | This concept is only valid while the target holds |
| `constrained-by` | The target limits what this concept may do |
| `part-of` | This concept is a constituent of the target, which is incomplete without it |
| `refines` | This concept narrows or sharpens the target |
| `specified-by` | The target is the specification of this concept |
| `implemented-by` | The target is the work that delivers this concept |
| `resolves` | This concept fully answers or closes the target |
| `partially-resolves` | This concept answers part of the target, which remains open |
| `tracked-by` | The target is the work-tracking record that chases this concept |
| `related-to` | An unlabelled association worth surfacing |

## Choose a name

- `part-of` is composition, not narrowing (`refines`).
- `resolves` means full closure; progress that leaves an item open is
  `partially-resolves`. `tracked-by` names who chases it in the tracker.
- Never write the same name back along an existing edge: backlinks are computed.
  A redundant reverse `related-to` is also wrong; different complementary names
  or genuine peer associations are fine.
- Repeated `related-to` may reveal a missing project name; declare it once.
- Deliberate unresolved internal targets remain loadable planned links (notes);
  repair accidental ones.

Ordinary Markdown links in the body remain valid untyped edges.

## Execution stays external

Tickets, issues, and pull requests live in the issue tracker. Link them with
`specified-by`, `implemented-by`, or `tracked-by`. Never mirror their state
into the bundle; a linked record's status lives only in the tracker. One
concept may link to several execution records or to none, and the count is
never a finding.

A tracker-owned specification is an execution record: link it, never mirror its
state. A durable specification that outlives the work and is cited as knowledge
is a `Specification` concept filed with its subject. Each has exactly one
lifecycle owner; never keep both a tracker record and a concept for it.
