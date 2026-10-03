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

`resource` is a link target: a bundle-relative path with a leading `/`, or a
URL. It is never a scope descriptor. Never put a relationship in `sources`,
which records what the content derives from and carries credibility in OKF.

## Standard names

The Profile package declares these names. Declare a project name in the
`wayfinder.json` entry's `relationships`, with a description that defines it
once. Never invent a name in a concept.

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

- Use `part-of` for composition: a constituent, not a narrowing. Two buckets
  that sum to a balance are `part-of` it, not `refines` it.
- Use `resolves` only for genuine closure. Evidence that moves an open item
  forward but leaves it open is `partially-resolves`. A loose `resolves`
  makes open items read as settled, the same error as an unearned `verified`.
- Use `tracked-by` for the record that carries who owes an open question and
  by when. The question stays in the bundle, and openness is still read from
  `resolves` and `partially-resolves`.
- Never write a name back along the same edge. Names read outward and
  backlinks are computed, so `refines` both ways says each concept narrows
  the other. `related-to` pointed back along an edge that already has a
  precise name is the same redundancy. Two different complementary names, or
  `related-to` between genuine peers, are fine.
- Reaching for `related-to` again and again means a name is missing. Declare
  a project name instead.
- An unresolved internal target stays a loadable edge and is reported only as
  a note. Keep a deliberate planned link. Repair a mistaken one.

Ordinary Markdown links in the body remain valid untyped edges.

## Execution stays external

Tickets, issues, and pull requests live in the issue tracker. Link them with
`specified-by`, `implemented-by`, or `tracked-by`. Never mirror their state
into the bundle; a linked record's status lives only in the tracker. One
concept may link to several execution records or to none, and the count is
never a finding.

A specification is a genre, not a location. A tracker owns an execution
record's state: a status, an assignee, a workflow the bundle does not
advance. A specification opened as a tracker issue is an execution record,
so link it and never mirror it. A specification the project maintains as
durable knowledge outlives the work it scoped, later concepts cite it, and
its only state is `status`. That is a `Specification` concept, filed with its
subject. Every durable specification has exactly one lifecycle owner, so it
never exists both as a tracker record and as a concept.
