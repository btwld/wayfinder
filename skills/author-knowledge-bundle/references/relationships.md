# Relationships

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply.

An optional `# Relationships` section gives selected links a stable label — one label, one target per bullet:

```markdown
# Relationships

- Superseded by: [new-term](/reporting/new-term.md)
- Refines: [parent-decision](/ways-of-working/parent-decision.md)
- Implemented by: [PR #42](https://github.com/org/repo/pull/42)
```

Preferred labels: Superseded by, Depends on, Constrained by, **Part of**, Refines, Specified by, Implemented by, Resolves, **Partially resolves**, **Tracked by**, Related to — each read from the containing concept outward. Additional labels are permitted and produce only a non-blocking advisory; a project should define one once in a durable `Guide` so later authors use it consistently. Prefer bundle-relative links (leading `/`) for internal targets. Ordinary markdown links elsewhere in the body are valid untyped edges. The ordinary OKF graph exposes every link, labelled or not, as the same untyped body edge; never add frontmatter or graph enrichment for a Profile relationship. `sources` carries provenance; Relationships carry body context — keep them separate.

- **`Part of`** for composition — a constituent, not a narrowing. Two buckets that sum to a balance are `Part of` it, not `Refines` and not peers. One direction only; backlinks are computed.
- **`Resolves` versus `Partially resolves`:** `Resolves` is genuine closure only. Evidence that moves an open item forward while leaving it open uses `Partially resolves`. Loose `Resolves` makes open items read as settled — the same class of error as an unearned `verified`.
- **`Tracked by`** points at the work-tracking record chasing this concept — the issue that carries who owes an open question and by when, while the question itself stays here. It is not `Specified by` or `Implemented by`, and it carries no state: openness is still read from `Resolves` / `Partially resolves`.
- **Never write the same label back.** Labels read outward, so `Refines` both ways says each concept narrows the other, and `Constrained by` both ways says a question and a rule gate each other. Backlinks are computed, never authored. `Related to` pointed back along an edge that already has a precise label is the same redundancy wearing a weaker one. Fine: `Related to` between genuine peers, and two *different* complementary labels.
- Reaching for `Related to` repeatedly means a label is missing. If it carries a large share of your edges, name the relationship instead.
- An unresolved internal target stays a loadable OKF edge and receives only a non-blocking advisory. Preserve a deliberate planned link; repair a mistaken one. Profile Review makes that contextual distinction.
