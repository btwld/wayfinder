# Structure and lifecycle

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply. This reference covers the bundle tree, directory
naming, placement, identity, moves, and retirement.

## Bundle structure

`index.md`, `log.md`, `profile.md`, and `types.md` are required at the bundle
root. Add `actors.md` whenever `generated.by`, `verified[].by`, or
`sources[].author` uses an actor ID; it must represent every used ID. `types.md`
uses exactly `Type | Intended content`; `actors.md` uses exactly `Actor ID | Name
| Organization | Side | Role | Active`. Both are ordinary body tables with no
custom frontmatter or graph meaning.

A bundle is one distribution unit and never contains a nested independently
distributed bundle.

```text
knowledge/
  index.md          ← root index: okf_version frontmatter, one entry per root concept, area, and references/
  log.md            ← root log: dated lifecycle entries, newest first
  profile.md        ← Knowledge Profile concept declaring the profile and OKF versions
  types.md          ← Type Registry concept: all standards plus registered extensions
  actors.md         ← Actor Registry when any OKF actor-valued field is used
  <concept>.md      ← a root concept
  <area>/           ← a subject directory: mixed types, its own index.md, may nest
  architecture/     ← the system as a whole: Architecture Documents and ADRs
  ways-of-working/  ← how the team works: process, conventions, guides, decisions about the bundle
  interactions/     ← Interaction Records, organized by date; may nest by cadence
  references/       ← OKF mirrored-source convention (mixed types allowed, may nest)
```

**Every project directory names a subject, never a kind of document.** Kind is carried by `type` and nowhere else, so there is no `decisions/`, `analyses/`, `guides/`, `rules/`, `questions/`, or `adr/` — a term, the rules deriving it, the questions about it, and the specification covering it all sit in one directory because they share a subject. `interactions/` and `references/` retain their Profile-defined time and source axes. Reading a kind as a set is an index filtered by `type`, not a directory.

`architecture/`, `ways-of-working/`, `interactions/`, and `references/` are the **only** directory names the profile fixes. Every other area name is the project's own vocabulary.

### Areas

- **Named after what its concepts share** — a capability, a domain, the system, the way the team works. An area name that matches one member concept's title is a signal the name is too narrow: it is named after a part of the set rather than the whole.
- **Mixed types.** An area holds any types. That is the point of it.
- **Earned, not predicted.** A genuine shared subject may have an area at any size; a numeric threshold cannot prove the placement. The Profile recommends against speculative areas for a taxonomy the current corpus does not demonstrate.
- **Indexed.** A nonempty area needs its own `index.md`.
- **Nestable** under the same rules. Prefer nesting when a subject genuinely subdivides; every path segment adds identity that external citations may freeze.
- **Prefer existing placement.** Normally put a new concept into an existing area or the parent directory, unless the current corpus supports a genuine shared subject for a new area. Creating an area is a deliberate act, recorded in `log.md` — the cost of a wrong area is a false claim about the subject of every concept placed there.
- **A subject concept is ordinary knowledge.** A specifically named concept may explain the area's subject when it carries durable knowledge. Never create a generic `overview.md` that merely duplicates the generated index; directory index entries have path-derived labels and no authored descriptions.

### Placement

A concept lives with its subject. A decision about billing goes in the billing area; a decision about how the team captures knowledge goes in `ways-of-working/`.

- **`architecture/` holds architecture whose subject is the system as a whole** — structure, technology, boundaries, integration contracts, and the ADRs that shaped them. Architecture whose subject is one capability lives in that capability's area: a data model for billing is billing knowledge that happens to be architectural. The type stays `Architecture Document` in both places. Placement follows subject, never type.
- **`interactions/` is the time-axis exception.** A dated record ordinarily spans several subjects, so no single area can host it. Its name matching its type is fine here and nowhere else: the axis is time, and a record spanning subjects scatters none of them. The durable-capture bar still applies — an interaction that produced one durable outcome contributes that outcome to *its* subject's area, not a record here. A thin `interactions/` is the expected shape.

Creating a bundle from nothing is the `adopt-knowledge-bundle` skill's job; its
[SEEDING.md](../../adopt-knowledge-bundle/SEEDING.md) holds the root files.

## IDs and lifecycle

- A concept's ID is its path from the bundle root without `.md`: `reporting/token-contract`. Use readable lowercase kebab-case for each authored slug. Put a date in the path only when chronology is intrinsic to stable identity (for example, Interaction Records and mirrored snapshots), never for creation time, freshness, workflow, or an editable version. Status, owner, priority, and Profile version never appear in filenames.
- **An ID other systems already cite is part of identity — preserve it verbatim, leading the path.** `d11-collected-revenue-basis`, `architecture/0008-direct-token-consumption`. Requirement numbers, rule codes, question numbers, ADR sequence numbers: never renumber, never trade one for a nicer name. They are cited in trackers, matrices, client documents, and scripts that grep them, so they are already frozen by citation — the concept adopts a frozen identity rather than minting a rival.
- **A concept may move at any `status`**, for as long as every reference to it can be repaired. A move is complete in one operation: inbound bundle links repointed, affected indexes regenerated, and a `* **Move**:` entry in `log.md` naming both paths. `status` never decides this — movability is about who points at the path, not how reviewed the document is, and holding a finished concept at `draft` to keep it movable is the `status` abuse the profile forbids.
- **A path freezes when a known citation outside the bundle cannot be repaired** — a tracker issue, a client deliverable, another repo, anywhere you cannot coordinate the update. A repairable external citation does not freeze it merely by crossing the boundary. Before moving a concept carrying `Specified by`, `Tracked by`, or `Implemented by`, you should inspect the linked execution record for citations; the relationship alone is not proof. If a citation cannot be repaired, retain the path and retire by `status: deprecated` plus a `Superseded by` link when a successor exists.
- Inside the bundle a broken link is tolerated by OKF and repairable by you, which is why the freeze sits at the boundary where neither is true.
- Stable concepts normally deprecate, and link an available successor with `Superseded by`. Drafts may simply be deleted. Hard-delete stable content only for an exceptional security, privacy, legal, secret-removal, or genuinely erroneous-content reason; Profile Review must assess the reason and known citations.
- **Moving concepts into a newly justified area is ordinary work**, not a migration. The current corpus, not a count, must make the shared subject truthful.
