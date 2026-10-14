# Converting an existing docs tree into a bundle

This method is generic. A project's own measurements and slice plan are
project artifacts and stay in the project, not in the bundle.

## Measure before deciding

Build these from the actual tree before planning any slice:

- a document inventory with sizes;
- every identifier scheme in use, and how many documents cite each;
- the cross-reference graph;
- every generator, script, and downstream artifact that reads the documents.

The last one is the one that gets skipped and the one that hurts. A tree with
two scripts that parse `FR-*` out of Markdown has constraints that no reading
of the documents reveals.

## Classify, then cluster

First classify each candidate concept by the `type` it would carry
([types.md](types.md)). This is a judgment about what a document is, made
before deciding where it lives.

Then cluster by subject. Areas come from genuine shared subjects in the
actual corpus ([structure.md](structure.md#areas)). No count settles it. A
small coherent cluster may be an area, and a large assortment with no
truthful shared subject may not.

Keep this order. Documents sorted by what they are always look like they
want folders named after what they are, so clustering first rebuilds the
kind-named tree.

## Granularity is the promotion rule at scale

Migration is where the promotion rule
([capture.md](capture.md#promote-or-embed-an-outcome)) does its heaviest
work. The source tree's granularity comes from how it was written, not from
what has a lifecycle. An outcome normally earns a concept when it needs
independent status, provenance, relationships, reuse, replacement, or
history. Apply that in context, and keep a reviewed exception when the
context supports it.

For example, take a requirements specification with 149 atomic requirements
across 17 capability areas. One concept per requirement gives each its own
`sources`, `verified`, and trust tier, which is the highest fidelity
available. It is also wrong. 149 concepts swamp their areas, and an atomic
requirement has no lifecycle apart from its capability area and the rule it
formalizes. Review recommends one concept per capability area, with the
requirements in the body and their IDs kept verbatim. Footnotes keyed to
`sources[].id` carry mixed provenance inside the concept
([metadata.md](metadata.md#sources)). The split test
([capture.md](capture.md#split-a-concept)) does not apply, because a
capability area is signed off as a unit or not at all.

Standing rules normally go the other way, one rule per concept. Each carries
its own provenance and trust tier, and averaging them would let a
well-evidenced rule lend its confidence to a thin one.

## Slice by subject, never by kind

A slice is one subject migrated whole, with its terms, rules, open
questions, specification, and analyses. Never migrate "all the glossary
this week".

- Order slices by dependency. Never start a slice whose inbound
  dependencies are not migrated yet.
- Do one slice per working session. A half-migrated subject has two sources
  of truth, which is what the migration exists to end.
- A slice is done only when every concept in it passes the per-concept
  write, a person has read its area index end to end, and
  `wayfinder validate` passes on the tree as it stands. The tree is hybrid for
  the whole migration, so validation must pass in the hybrid state too.

Placement is reviewed, not validated. Nothing mechanical detects a concept
filed under the wrong subject. Only a person reading the area index does.

## Three invariants

Every migration carries these three, whatever the project:

1. **Never promote evidence.** Reformatting is not confirmation. Keep every
   truthful `verified` event, and add a new one only when an actor genuinely
   confirms the content against its sources or `resource`
   ([metadata.md](metadata.md#production-and-verification)). A `verified`
   event added as a migration formality turns an internal reading into
   apparent sign-off, and nothing in the record tells the two apart.
2. **IDs survive verbatim.** An identifier the outside world cites is
   already frozen ([structure.md](structure.md#ids-and-paths)). Never
   renumber during a migration. That is when renumbering is most tempting
   and does the most damage.
3. **Supersession is preserved, not deleted.** Superseded material migrates
   as `deprecated` concepts with a `superseded-by` relationship, so the
   history stays inspectable ([structure.md](structure.md#retirement)). A
   migration that drops what was replaced destroys the record of how
   understanding moved.

## Inventory, then fix only what is mechanical

Before editing, inventory missing baseline fields, used and standard types,
producer-defined fields, actor history, tags, and materially derived claims.

Mechanical normalization may declare used project types in `wayfinder.json`
and reshape supported syntax. Never guess a title, description, `status`,
generation actor, verification event, affiliation, freshness horizon, or
source. Those gaps carry truth, so they stay visible for review until
evidence supplies the value.

For each producer-defined field, decide where its value goes before removing
the key. Move the information to an OKF field that applies, or to body
prose, and keep any unknown provenance and meaning. When no truthful mapping
is known, leave the gap visible for review instead of deleting it.

## Review the capture boundary

Review existing meeting notes, source-event documents, and Interaction
Records against the durable-knowledge test
([capture.md](capture.md#source-events-are-not-concepts)). Retire or reshape
routine minutes that have no durable combined context. For other outcomes,
apply the promotion and splitting guidance in
[capture.md](capture.md). A reviewed exception may stay embedded or combined.
A filename or a type cannot make that decision.

## Relationships, execution records, and mirrors

Inventory labelled relationships, tracker-owned artifacts, specifications,
externally cited concept IDs, planned moves, stable concepts chosen for
retirement, and mirrored material.

- Write labelled links as `relationships` entries mechanically
  ([relationships.md](relationships.md)).
- Leave the rest to review. That covers path conformance, relationship
  meaning, lifecycle ownership, intrinsic chronology, whether a citation can be
  repaired, deletion exceptions, and for mirrors the classification,
  placement, availability risk, visibility, sanitization, image
  optimization, and media type ([mirroring.md](mirroring.md)).
- Move media that review identifies as prohibited out of the repository.
- Complete each repairable move in one operation. Update known links,
  indexes, and the log together. A known external citation that cannot be
  repaired freezes the path
  ([structure.md](structure.md#moves-and-frozen-paths)).
- Keep a followable external source as a followable OKF resource when you
  do not mirror it. Never replace it with a scope descriptor to avoid an
  availability advisory
  ([mirroring.md](mirroring.md#deciding-not-to-mirror)).

A project may add its own invariants. A sanitization boundary that excludes
credentials, prices, or raw transcripts is common. Record them where the
migration runs, not in the bundle's knowledge.

## Retire the old tree

Before the first slice, decide whether the old tree is fully replaced or
phased out, and record the choice as a `Decision` concept. Either works.
Leaving it undecided does not, because every slice then decides it again.
Full replacement is faster and ends drift sooner. Phased retirement is safer
per step and keeps a working package throughout, at the cost of two
authoritative homes while it runs.

Either way, generated deliverables and the scripts behind them read the old
documents. Give each one a replacement that reads the bundle before the
documents it reads disappear.

Review the migrated bundle with **Scope: whole bundle** per
[review-map.md](review-map.md).
