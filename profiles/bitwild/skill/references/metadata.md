# Metadata, provenance, and trust

OKF §4 and §5 own the syntax and meaning of every field below. Copy YAML
shapes for `generated`, `verified`, `sources`, and `tags` from the pinned
spec. This reference adds only what the Profile decides.

## Baseline frontmatter

The [package rules](https://github.com/btwld/wayfinder/blob/main/profiles/bitwild/README.md)
enforce baseline fields and allowed keys; choose truthful values. The generated
index copies `description` verbatim. Readers preserve unknown fields despite
producer restrictions. Copy syntax from pinned OKF §§4–5, including timestamp
UTC offsets; migrate date-only values with `okf format --migrate-timestamps`.

## Status

`status` describes the document's knowledge lifecycle: `draft`, `stable`, or
`deprecated`. Workflow states such as accepted, blocked, in progress, or done
belong to the issue tracker. Never hold a finished concept at `draft` to keep
it movable; movability depends on citations, not status
([structure.md](structure.md#moves-and-frozen-paths)).

## Tags

Tags carry topic only, never kind, lifecycle, trust or settledness. For example,
`partially-resolved` restates relationships and becomes wrong when closure changes.
Use tags declared by the selected Profile chain or the project's binding; add
project-local topics there without redeclaring package tags. Do not tag
`captures` just because there is a source citation.

## Sources

When a claim materially derives from identifiable source material, record
that material in OKF `sources`. Original analysis, guidance, and decisions
need no source. Never invent a source to satisfy this rule. Validation checks
only the shape of present sources and the footnote joins, so whether material
provenance is missing is a review judgment.

Attribute individual claims with body footnotes whose labels equal a
`sources[].id`.

## Production and verification

Keep production and confirmation distinct.

- Add `generated: {by, at}` when the producer and the time of the meaningful
  change are known. It is recommended, not required. Never invent either
  value, including to clear the `generation-provenance-recommended`
  advisory. A meaningful rewrite during authoring or migration can truthfully
  update `generated` without verifying any claim.
- Add a `verified` event only when the named actor actually confirmed the
  content against its sources or `resource`. Review, migration, or
  conformance work alone is not that confirmation.
- A missing `verified` is a signal, not a defect. A concept that records
  unconfirmed material is correctly unverified. Never add a verification
  event to satisfy a convention, a checklist, or a linter, and never report
  missing verification as a finding.
- The verifier may be a person, an agent, or a process.

Never invent a maturity, confidence, credibility, or evidence-tier field.
Use OKF's own signals and attribution without restating them.

## Actors

Trust tiers distinguish human from machine, not client from internal. The
actor lookup in `wayfinder.json` may record an optional `side`: `client`,
`internal`, `vendor`, `tool`, or `unknown`. Use `unknown` when the
affiliation is not known; never infer it from an actor ID. Keep every field
of an actor record truthful. The lookup holds one current record per actor
ID, so it cannot carry a dated affiliation history; a project that needs one
records it as ordinary knowledge. The lookup never changes the actor string,
its OKF prefix, or its derived trust tier.

## How settled the subject is

Describe settledness beside its reasoning in the body, with what would settle it
and who can answer when useful. Keep it out of frontmatter/status. An optional
shared vocabulary belongs once in `ways-of-working/`. Links do not establish
settledness: a constraint may be settled, broken links are valid and absence is
silence. Verified first-party content can still describe an unsettled subject.

## Freshness

Add `stale_after` only when evidence supports a real freshness horizon for
the content. Never use it as a default for a type or as a conformance
placeholder.
