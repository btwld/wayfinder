# Structure, identity, and lifecycle

The bundle root holds `index.md` and `log.md`. Project configuration lives
in the project-root `wayfinder.json`, never in the bundle, so never create a
root `profile.md`, `types.md`, or `actors.md` registry. A bundle is one
distribution unit and never contains a nested bundle.

```text
knowledge/
  index.md          generated root index, declares okf_version
  log.md            authored lifecycle log, newest first
  <concept>.md      a root concept
  <area>/           a subject directory: mixed types, its own index.md, may nest
  architecture/     the system as a whole: Architecture Documents and ADRs
  ways-of-working/  how the team works: process, conventions, guides, bundle decisions
  interactions/     Interaction Records by date; may nest by cadence or kind
  references/       mirrored sources by source and date; may nest
  computations/     Attested Computation concepts only; may nest
```

Every directory is optional and created lazily. Ordinary concepts may sit at
the root.

## Name directories after subjects

Every project directory names the subject its concepts share, never a kind of
document. Kind lives in `type`, so there is no `decisions/`, `analyses/`,
`guides/`, `rules/`, `questions/`, or `adr/`. A term, the rules that derive
it, the questions about it, and its specification share one directory
because they share a subject. Reading every concept of one kind is an index
filtered by `type`, not a directory.

## Areas

An area is a directory that holds every concept whose subject is one thing.

- Name it after what its concepts share, in the project's own vocabulary: a
  capability, a domain, the system, or the way the team works. A name that
  matches one member's title is too narrow. Prefer the broader subject and
  keep the term as a peer concept.
- It holds any mix of types.
- Earn it from the current corpus. A genuine shared subject may have an area
  at any size, and no count proves the placement. Do not create speculative
  structure for subjects the corpus does not show yet.
- File a new concept into an existing area or the parent directory unless
  the corpus supports a genuine shared subject for a new one. Creating an
  area is deliberate: log it with an `Area created` entry. A wrong area makes
  a false claim about the subject of every concept filed in it.
- Nest only when a subject genuinely subdivides. Every path segment is
  identity that an external citation may freeze.
- An area may hold a specifically named concept with durable knowledge about
  its subject. Never create a generic `overview.md` or any concept that
  duplicates the generated index.

## Fixed directories

Only these five directory names are fixed; others are project vocabulary:

| Directory | Membership |
| --- | --- |
| `architecture/` | System-wide structure, technology, boundaries, contracts and ADRs; capability-specific architecture stays with its capability. |
| `ways-of-working/` | Process, conventions, operational/engineering guidance and bundle decisions. |
| `interactions/` | Durable combined interaction context; may nest by cadence/kind. Single outcomes go with their subject, so a thin directory is expected. |
| `references/` | [Mirrored material](mirroring.md), organized by source/date, not subject; may nest. |
| `computations/` | Only OKF §10.4 Attested Computations and indexes; may nest by shared subject/runtime. Computations may instead live with their subject; consumers stay with theirs and link to them. |

## Placement

Place concepts with their subject: billing decisions in billing, knowledge-process
decisions in `ways-of-working/`. Type never determines placement.

## IDs and paths

A concept's ID is its path from the bundle root without `.md`, such as
`reporting/token-contract`.

- Write each authored slug in readable lowercase kebab-case.
- Preserve an identifier other systems already cite verbatim, at the start
  of the path: `d11-collected-revenue-basis`,
  `architecture/0008-direct-token-consumption`. Requirement numbers, rule
  codes, question numbers, and ADR numbers keep their case and are never
  renumbered or traded for a nicer name.
- Put a date in a path only when chronology is part of stable identity, as
  for Interaction Records and mirrored snapshots. Never encode creation time,
  freshness, workflow, or an editable version in it.
- Never put status, owner, priority, or a Profile release in a filename.

## Moves and frozen paths

A concept may move at any `status` while every reference to it can be
repaired. Complete a move in one operation: repoint inbound bundle links,
regenerate the affected indexes, and log a `Move` entry naming both paths.

A path freezes when a known citation outside the bundle cannot be repaired:
a tracker issue, a client deliverable, another repository, or anywhere you
cannot coordinate the update. Never change a frozen path. A repairable
external citation does not freeze a path just by crossing the boundary.
Inside the bundle a broken link is tolerated by OKF and repairable by you,
so the freeze sits at the boundary.

Before moving a concept with a `specified-by`, `tracked-by`, or
`implemented-by` relationship, inspect the linked execution record for
citations. The relationship alone proves nothing. If a citation cannot be
repaired, keep the path and retire the concept instead.

Moving concepts into a newly justified area is ordinary work, not a
migration.

## Retirement

- Retire a stable concept by setting `status: deprecated`, not by deleting
  it.
- A deprecated concept with a successor carries a `superseded-by`
  relationship to it.
- A draft may simply be deleted.
- Hard-delete stable content only for an exceptional security, privacy,
  legal, secret-removal, or genuinely erroneous-content reason that
  outweighs historical preservation. Review assesses the reason, the known
  citations, and any successors.

## The log

Log knowledge lifecycle events only: creating a concept, a substantive
change, a deprecation, a replacement, a move with both paths, and creating
an area. Prefer the lead words `Initialization`, `Creation`, `Update`,
`Move`, `Area created`, and `Deprecation` when one fits. Never log a source
event that produced no durable knowledge, a formatting-only edit, or
unrelated repository activity.
