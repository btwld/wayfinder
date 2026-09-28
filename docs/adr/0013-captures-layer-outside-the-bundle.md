# ADR-0013: Keep capture evidence outside the knowledge bundle

- Status: proposed; no Profile convention established
- Date: 2026-09-11
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
unaltered. The [adoption skill](../../skills/adopt-knowledge-bundle/SKILL.md)
already describes this optional workflow and its visibility check; the
[seed template](../../skills/adopt-knowledge-bundle/SEEDING.md#captures)
owns its current file layout. Neither makes it a Profile conformance rule.

A project may register a `Source Document` custom type for a concept that
points to an externally maintained document through OKF
`sources[].resource`. The concept describes its coverage and relevant
differences without restating the document. `Source Document` is not a
standard type in Profile 2026.3. Whether it should become one needs
cross-project evidence and the Profile release process.

## Rationale and consequences

OKF treats Markdown inside a bundle as concepts; intake notes are evidence,
not durable knowledge. Keeping them outside prevents raw source material
from silently entering Wayfinder's knowledge index. Repository visibility
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
