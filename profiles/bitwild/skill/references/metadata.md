# Metadata, provenance, and trust

OKF §4 and §5 own the syntax and meaning of every field below. Copy YAML
shapes for `generated`, `verified`, `sources`, and `tags` from the pinned
spec. This reference adds only what the Profile decides.

## Baseline frontmatter

Every concept carries nonempty `type`, `title`, `description`, and `status`.
Choose truthful values for each. `description` is one sentence, and the
generated index copies it verbatim.

Write only OKF-defined keys plus `relationships`. Readers still preserve
unknown keys, because this producer restriction does not change OKF's
tolerant-reader contract.

Every timestamp names an instant, so it carries a UTC offset. A date-only or
offset-less value raises `okf/timestamp-without-offset`.
`okf format --migrate-timestamps` rewrites such values to the datetime form.

## Status

`status` describes the document's knowledge lifecycle: `draft`, `stable`, or
`deprecated`. Workflow states such as accepted, blocked, in progress, or done
belong to the issue tracker. Never hold a finished concept at `draft` to keep
it movable; movability depends on citations, not status
([structure.md](structure.md#moves-and-frozen-paths)).

## Tags

Tags carry topic and nothing else. Never use a tag as an alias for kind
(`type`), lifecycle (`status`), trust (derived from `verified`), or how
settled the subject is (body prose). A tag that restates one of those is
redundant when written and wrong once the real signal moves. For example,
`partially-resolved` on a question restates an inbound edge, and nothing
updates the tag when a second edge lands.

Declare every used tag once in the project's `wayfinder.json` entry. Do not
use `captures` as a tag merely because a concept cites evidence.

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

State how settled the subject is in the body, beside the reasoning that
justifies it, with pointers to what would settle it. Never put it in
frontmatter or `status`, which describe the document. Which party can answer
an open point may also stay in the body.

A shared settledness vocabulary is optional. If the project adopts one,
define it once in a `ways-of-working/` concept.

Settledness is not derivable from links. `constrained-by` may target a fully
settled constraint, broken links are valid, and an absent link is silence,
not evidence. A concept can be first-party and verified and still describe
an unsettled subject.

## Freshness

Add `stale_after` only when evidence supports a real freshness horizon for
the content. Never use it as a default for a type or as a conformance
placeholder.
