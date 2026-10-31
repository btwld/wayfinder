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

For example, 149 atomic requirements across 17 capabilities may belong in 17
concepts **if each capability is verified and evolves as one unit**. Preserve
requirement IDs in the body and attribute individual claims with source footnotes.
If requirements have independent owners, verification, dependencies or replacement
history, separate concepts can be appropriate. Neither document count nor atomic
wording settles granularity; apply the promotion and split tests to the corpus.

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

Review meeting notes and Interaction Records with [capture.md](capture.md),
including durable context, promotion and split tests. A type/filename cannot
settle these; retain reviewed exceptions.

## Relationships, execution records, and mirrors

Inventory labelled links, tracker artifacts, specifications, cited IDs, moves,
retirements and mirrors. Mechanically encode labelled links as `relationships`;
review meaning and lifecycle ownership with [relationships.md](relationships.md).
Use [structure.md](structure.md#moves-and-frozen-paths) for frozen paths, atomic
move repair and retirement; use [mirroring.md](mirroring.md) for availability,
visibility, sanitization, media and followable resources. Move prohibited media
out of the repository. A project may add its own sanitization boundaries; record
them with the migration artifacts, not as bundle knowledge.

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
