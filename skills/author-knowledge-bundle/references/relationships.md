# Relationships

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply.

A relationship gives one link a stable, typed meaning, read from the containing
concept outward. It is written in the top-level frontmatter key
`relationships`, a list of mappings with exactly `relationship` (a declared
name) and `resource` (the target). A `# Relationships` body heading is
ordinary prose: it types nothing, and validation does not read it.

## The `relationships` key

```yaml
relationships:
  - relationship: superseded-by
    resource: /reporting/new-term.md
  - relationship: refines
    resource: /ways-of-working/parent-decision.md
  - relationship: implemented-by
    resource: https://github.com/org/repo/pull/42
```

`resource` is a link target: a bundle path, bundle-relative (leading `/`) for
internal targets, or a URL. It is never a scope descriptor. Never put a
relationship in `sources`: `sources` records what the content derives from,
and OKF lets credibility propagate through it.

The standard names, declared by the base Profile manifest:

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

Every name you use must be declared. A project name goes in the binding's
`relationships` list in `wayfinder.json`, with a description that defines it
once; never invent a name in a concept. An undeclared name, a missing or empty
`resource`, an extra key, or a `relationships` value that is not a list fails
validation. A non-bundle-relative internal target is only an advisory, and an
unresolved one only a summary entry. Ordinary Markdown links in the body remain valid untyped edges.

## How to choose a name

- **`part-of`** for composition — a constituent, not a narrowing. Two buckets that sum to a balance are `part-of` it, not `refines` and not peers. One direction only; backlinks are computed.
- **`resolves` versus `partially-resolves`:** `resolves` is genuine closure only. Evidence that moves an open item forward while leaving it open uses `partially-resolves`. Loose `resolves` makes open items read as settled — the same class of error as an unearned `verified`.
- **`tracked-by`** points at the work-tracking record chasing this concept — the issue that carries who owes an open question and by when, while the question itself stays here. It is not `specified-by` or `implemented-by`, and it carries no state: openness is still read from `resolves` / `partially-resolves`.
- **Never write the same name back.** Names read outward, so `refines` both ways says each concept narrows the other, and `constrained-by` both ways says a question and a rule gate each other. Backlinks are computed, never authored. `related-to` pointed back along an edge that already has a precise name is the same redundancy wearing a weaker one. Fine: `related-to` between genuine peers, and two *different* complementary names.
- Reaching for `related-to` repeatedly means a name is missing. If it carries a large share of your relationships, declare a project name instead.
- An unresolved internal target stays a loadable edge and is reported only as a summary entry. Preserve a deliberate planned link; repair a mistaken one. Profile Review makes that contextual distinction.
