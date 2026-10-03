# ADR-0013: Keep capture evidence outside the knowledge bundle

- Status: proposed
- Date: 2026-09-11
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0013-captures-layer-outside-the-bundle.md))
- Scope: optional evidence workflow and a possible future Profile type

## Context

An adoption with externally maintained documents and event records exposed
two failure modes: concepts restated another owner's documents, creating a
second source of truth, and event context had to be reconstructed each time.
Routine minutes are not durable OKF concepts, but source evidence still needs
a place to live and be cited. The existing `references/raw/` tier serves
at-risk originals mirrored for a concept; it is not an event-intake layer.

## Proposal

Keep `captures/` beside, not inside, the OKF bundle. Group originals by dated
source event or delivery, with an `intake.md` recording provenance,
participants, originals and hashes, sensitivity, a bounded summary,
contradictions, open questions, and the concepts supported. Keep originals
unaltered. The Bitwild Profile skill's
[captures reference](../../profiles/bitwild/skill/references/captures.md)
describes this optional workflow, its visibility check, and its current file
layout. Neither makes it a Profile conformance rule.

A project may register a `Source Document` custom type for a concept that
points to an externally maintained document through OKF
`resource`. The concept describes its coverage and relevant
differences without restating the document. `Source Document` is not a
standard type in Profile 2026.3. Whether it should become one needs
cross-project evidence and the Profile release process.

## Consequences

Keeping intake notes outside the bundle prevents raw source material from
silently entering Wayfinder's knowledge index. Repository visibility
still governs access to captures, so adopting the layout is not permission
to commit previously untracked sensitive originals.

Existing bundles remain conformant without captures. A raw `captures/`
directory is not a searchable OKF bundle. A project that needs searchable
captures must deliberately represent them as a separate conformant bundle
with its own binding.

Knowledge lifecycle and verification remain separate: `status` follows
OKF's document lifecycle, while `verified` records only an actual
verification event. A capture alone implies neither stability nor
verification. When evidence and a concept disagree, review the source and
correct any inaccurate knowledge; do not promote the intake note into an
authoritative concept by default.

## Decision gate

Keep this ADR proposed until more than one project demonstrates the same
capture boundary and the Profile release process decides whether `Source
Document` or any capture metadata needs a generic convention. Until then,
projects may use the workflow as optional implementation guidance only.
