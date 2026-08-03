---
name: concepta-okf-profile
description: Read and write the knowledge bundle at knowledge/ per the Concepta OKF Profile (OKF 0.2). Use before creating, editing, deprecating, or moving any concept under knowledge/, when mirroring source material into references/, or when another skill needs the profile's conventions.
---

# Concepta OKF Profile

The knowledge bundle at `knowledge/` is an Open Knowledge Format (OKF) bundle following the Concepta OKF Profile — versions declared in `knowledge/profile.md`. The profile is a thin layer on **OKF 0.2**, which is authoritative: it says *which* knowledge is worth storing, *where* it goes, and *how* concepts link, and it defines no file type, no frontmatter field, and no metadata semantics of its own. Nothing here overrides the [OKF specification](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/3fcbb9f828c2f23d109c855ee403c3a4c81f3a96/okf/SPEC.md), pinned to the 0.2 commit and vendored at [OKF-0.2.md](./OKF-0.2.md).

**Where this skill is silent, OKF 0.2 governs.** Silence means the upstream spec already settles the point, so read it and follow it — never invent a Concepta convention to fill a gap. See [Beyond this profile](#beyond-this-profile) for what that covers in practice. Within what the profile *does* specify, concepts take these shapes and never invented ones.

## Bundle structure

```
knowledge/
  index.md          ← root index: okf_version frontmatter, one entry per root concept, area, and references/
  log.md            ← root log: dated lifecycle entries, newest first
  profile.md        ← Knowledge Profile concept declaring the profile and OKF versions
  types.md          ← Type Registry concept: every type this bundle uses, one line each
  actors.md         ← Actor Registry concept: every actor ID → organization, side, role
  <concept>.md      ← a concept whose subject has not earned an area yet
  <area>/           ← a subject directory: mixed types, its own index.md, may nest
  architecture/     ← the system as a whole: Architecture Documents and ADRs
  ways-of-working/  ← how the team works: process, conventions, guides, decisions about the bundle
  interactions/     ← Interaction Records, organized by date; may nest by cadence
  references/       ← OKF mirrored-source convention (mixed types allowed, may nest)
```

**Every directory names a subject, never a kind of document.** Kind is carried by `type` and nowhere else, so there is no `decisions/`, `analyses/`, `guides/`, `rules/`, `questions/`, or `adr/` — a term, the rules deriving it, the questions about it, and the specification covering it all sit in one directory because they share a subject. Reading a kind as a set is an index filtered by `type`, not a directory.

`architecture/`, `ways-of-working/`, `interactions/`, and `references/` are the **only** directory names the profile fixes. Every other area name is the project's own vocabulary.

### Areas

- **Named after what its concepts share** — a capability, a domain, the system, the way the team works. An area name that matches one member concept's title is a signal the name is too narrow: it is named after a part of the set rather than the whole.
- **Mixed types.** An area holds any types. That is the point of it.
- **Earned at three.** Create an area when at least three concepts share its subject. Below that, concepts sit in the parent directory — including the bundle root, which is what makes waiting cheap. The four profile-fixed names are exempt: `architecture/`, `ways-of-working/`, `interactions/`, and `references/` may be created for their first concept, because a name the profile fixes cannot turn out to be the wrong name.
- **Indexed.** A nonempty area needs its own `index.md`.
- **Nestable** under the same rules, but every path segment is identity, so nest only when a subject genuinely subdivides.
- **File, don't create.** Put a new concept into an existing area or at the root. Creating an area is a deliberate act, recorded in `log.md` — the cost of a wrong area is not a wrong folder, it is a path, and a path is identity.
- **No concept describes a directory.** OKF reserves two directory-level filenames, `index.md` and `log.md`, and neither is a concept — so never a sibling `<area>.md`, never an `overview.md`, never a concept whose content is the area's own contents. An area is described by its index and by the one-line description its parent index gives it.

### Placement

A concept lives with its subject. A decision about billing goes in the billing area; a decision about how the team captures knowledge goes in `ways-of-working/`.

- **`architecture/` holds architecture whose subject is the system as a whole** — structure, technology, boundaries, integration contracts, and the ADRs that shaped them. Architecture whose subject is one capability lives in that capability's area: a data model for billing is billing knowledge that happens to be architectural. The type stays `Architecture Document` in both places. Placement follows subject, never type.
- **`interactions/` is the time-axis exception.** A dated record ordinarily spans several subjects, so no single area can host it. Its name matching its type is fine here and nowhere else: the axis is time, and a record spanning subjects scatters none of them. The durable-capture bar still applies — an interaction that produced one durable outcome contributes that outcome to *its* subject's area, not a record here. A thin `interactions/` is the expected shape.

Creating a bundle from nothing: [SEEDING.md](./SEEDING.md) holds the root files.

## What earns a concept

A source event is only a source. A daily, planning session, demo, call, message, or transcript **never** becomes a concept merely because it happened. A concept is earned when the event produced durable knowledge: a meaningful request, a decision, an investigation and its findings, an architectural constraint, a term, a standing rule, a named unknown, or reusable guidance. An event that produced none of those leaves nothing behind, and that is a correct outcome rather than a gap — the bar is what keeps the bundle from degenerating into a meeting archive.

Requests are ordinarily first-class: a request outlives the conversation that expressed it and can later be analyzed, specified, implemented, rejected, or superseded, which is a lifecycle of its own.

**Promotion is decided by identity, not importance.** Given an outcome — a decision, an answer, an unknown — ask whether it has a lifecycle outside the concept where it arose:

- **Keep it embedded** when it has no meaningful identity of its own. A small outcome that will never be referenced, verified, or superseded on its own stays where it arose, as a heading in that concept's body.
- **Promote it to its own concept** when it needs independent status, provenance, relationships, reuse, replacement, or history.

An ambiguous outcome starts embedded, because un-promoting it is free until something outside the bundle cites its path. The same test decides a `Question`: a named unknown with an evidence trail, several dependents, or an ID cited outside the bundle is a concept; a single unknown belonging to one concept, with nothing recorded but the gap itself, is a heading in that concept's body.

An **Interaction Record** is the narrower case of the same rule: write one only when an interaction's *combined* context is itself durable — several linked outcomes, a negotiation, a demo whose overall shape matters. When one outcome mattered, that outcome links straight to its external source and no record is written. Never produce one as routine minutes.

## Types

`type` is the only place kind is carried — not the directory, not the filename, not a tag. Every type a bundle uses is listed in `knowledge/types.md` with a one-line meaning. The default vocabulary:

| Type | Intended content |
| --- | --- |
| `Glossary Definition` | One project or domain term |
| `Business Rule` | One standing business rule, constraint, invariant, or policy |
| `Question` | One named unknown: what is known, what is missing, what would close it |
| `Request` | A durable request from any relevant source |
| `Analysis` | An investigation, feasibility study, comparison, or recommendation |
| `Decision` | A durable non-architectural decision with an independent lifecycle |
| `Architecture Decision Record` | An architectural decision in ADR form |
| `Architecture Document` | A durable description of the system architecture |
| `Specification` | A specification the project maintains as durable knowledge, not one a tracker owns the state of |
| `Guide` | Durable operational or engineering guidance |
| `Interaction Record` | An interaction whose combined context is itself durable |
| `Knowledge Profile` · `Type Registry` · `Actor Registry` | The three defined root concepts |

Add a project-specific type only when the defaults genuinely don't fit, and register it in `types.md` when you do. When reading, tolerate unknown types, fields, and relationship labels — valid OKF you don't recognize is content to preserve, not an error, and the registry is never grounds for rejecting a concept.

- **`Business Rule` is formalism-neutral.** One standing rule per concept. Structure them with SBVR or any other notation the domain suits; the type commits to one-rule-per-concept, not to a notation.
- **`Architecture Decision Record` versus `Decision`:** use the ADR type when the decision shapes the software's structure and an engineer deciding how to build would read it; `Decision` for every other durable decision — process, commercial, scope, governance. When both fit, prefer `Decision`.
- **A `Business Rule` is not a `Decision`.** A rule describes how the business already works; a decision records a choice with alternatives.
- **A `Question` carries no state in its type or its path.** Whether it is still open is read from inbound relationships: `Resolves` means closed, `Partially resolves` means narrowed, neither means open. A resolved question stays `stable` — how understanding arrived at an answer is knowledge in its own right.
- **Splitting a concept:** split when parts would carry materially different provenance, verification, or lifecycle — frontmatter applies to the whole concept, and averaging trust across it is lossy. Mixed *provenance* is fine (footnotes handle it); mixed *verification* is the signal to split. Size alone is not.

## Baseline frontmatter

Every concept carries:

```yaml
---
type: <Concept type, e.g. Glossary Definition>
title: <Display name>
description: <One sentence; copied verbatim into the area index>
status: draft | stable | deprecated
generated: { by: <actor>, at: <ISO 8601 datetime> }
---
```

- **Actor convention**: `<producer>/<version>` for agents (e.g. `claude-code/fable-5`), `human:<id>` for people, `process:<id>` for automation.
- **Status** is knowledge lifecycle only — `draft`, `stable`, `deprecated`. Workflow states (accepted, blocked, in progress, done) belong to the issue tracker.
- Add native OKF fields (`tags`, `resource`, `stale_after`) when their OKF-defined meaning applies. `sources` and `verified` have their own section below.
- **`tags` carry topic and nothing else** — never kind (that is `type`), lifecycle (`status`), trust (derived from `generated`/`verified`), or a judgment about how settled the subject is (body prose). A tag restating one of those is redundant when written and wrong once the real signal moves: `partially-resolved` on a question is a fact about an inbound edge, and nothing updates it when a second edge lands.
- Only OKF-defined fields, ever — the profile adds no custom frontmatter.

## Provenance and trust

The profile defines nothing here — OKF §5 does, and these signals are what make a concept's credibility judgeable. Use them; never invent a maturity, confidence, or credibility field.

```yaml
sources:
  - id: demo-0730                                        # needed when the body cites this source
    resource: /references/2026-07-30-demo-transcript.md  # REQUIRED: URL, bundle path, or scope descriptor
    title: Reporting demo transcript, 30 July 2026
    author: human:chris                                  # who produced the source — an authority signal
    last_modified: 2026-07-30                            # recency of the source itself
verified:
  - { by: human:chris, at: 2026-07-31T09:00:00Z }
  - { by: process:finance-nightly, at: 2026-08-01T02:00:00Z }
```

- **`generated` vs `verified`**: `generated` records who *wrote* the current content; `verified` records who *confirmed* it against its sources. A concept whose content **asserts confirmed fact** should carry at least one `verified` event. The trigger is the content, never the `status` — a reviewed, `stable` concept that deliberately records an assumption is correctly unverified.
- **`verified` is a list** of independent confirmation events, so a human sign-off and a nightly process can both appear. A bare `{ by, at }` mapping is a one-element list. "How recently" is the latest `at`.
- **Trust tiers are derived, not stored** (OKF §5.3): no `verified` ⇒ *unverified*; non-`human:` actors only ⇒ *machine-confirmed*; any `human:<id>` ⇒ *human-reviewed*. So "this is not signed off by X" is expressed by the **absence** of a `verified` entry from X — write one only when someone genuinely confirmed the content, never as a migration formality.
- **Absence of `verified` is a signal, not a defect.** A concept deliberately recording unconfirmed material is *correctly* unverified. Never add a verification event to satisfy a convention, a checklist, or a linter; tooling must not report missing verification as a finding.
- **Organizational identity is not in the tier.** Trust tiers distinguish human from machine, not client from internal. That distinction lives in `knowledge/actors.md`, which maps every actor ID to its organization, side (`client` / `internal` / `vendor` / `tool` / `unknown`), role, and active range. A third-party authoring agent is `tool`; a process the project itself runs is `internal`, because its output is the project's own assertion. Never encode affiliation into an actor ID — `human:acme/jane-doe` puts a mutable attribute inside an immutable key and forces a rewrite of every field citing it when affiliation changes. Never guess an affiliation: an actor missing from the registry reads as unknown, and the concept still reads fine.
- **Credibility is inferred, never scored.** OKF records objective per-source signals — `author`, `last_modified`, and `usage_count` over a `usage_window` — and leaves the judgment to the consumer, because a stored score is subjective, unportable, and goes stale. Adding a confidence, maturity, or evidence-tier field is the one thing OKF deliberately refuses.
- **Per-claim attribution** uses a markdown footnote whose label is a `sources[].id`, so one concept can carry claims of differing provenance:

  ```markdown
  Reviewer annotations must survive the PDF export.[^demo-0730]

  [^demo-0730]: Reporting demo transcript, 30 July 2026
  ```

- **How settled the *subject* is belongs in the body, not in frontmatter and not in `status`.** `status` describes the document — OKF's `draft` means "not yet reviewed". State the assessment beside the reasoning that justifies it, with pointers to what would settle it; define the vocabulary once in a `ways-of-working/` concept. It is **not derivable from links**: `Constrained by` may target a fully settled constraint, broken links are valid, and absence of links is silence rather than evidence. A concept can be first-party, verified, and still describe an unsettled subject.

## IDs and lifecycle

- A concept's ID is its path from the bundle root without `.md`: `reporting/token-contract`. Lowercase kebab-case; dates only where chronology is identity (Interaction Records, mirrored snapshots). Status, owner, and priority never appear in filenames.
- **An ID other systems already cite is part of identity — preserve it verbatim, leading the path.** `d11-collected-revenue-basis`, `architecture/0008-direct-token-consumption`. Requirement numbers, rule codes, question numbers, ADR sequence numbers: never renumber, never trade one for a nicer name. They are cited in trackers, matrices, client documents, and scripts that grep them, so they are already frozen by citation — the concept adopts a frozen identity rather than minting a rival.
- **A concept may move at any `status`**, for as long as every reference to it can be repaired. A move is complete in one operation: inbound bundle links repointed, affected indexes regenerated, and a `* **Move**:` entry in `log.md` naming both paths. `status` never decides this — movability is about who points at the path, not how reviewed the document is, and holding a finished concept at `draft` to keep it movable is the `status` abuse the profile forbids.
- **A path freezes once it has been cited outside the bundle** — a tracker issue, a client deliverable, another repo, anywhere you cannot repair the citation. From then on, retire by `status: deprecated` plus a `Superseded by` link, never by moving. A concept carrying `Specified by`, `Tracked by`, or `Implemented by` toward an execution record has usually crossed that line already; treat it as frozen unless you know otherwise.
- Inside the bundle a broken link is tolerated by OKF and repairable by you, which is why the freeze sits at the boundary where neither is true.
- Hard deletion is reserved for security, privacy, legal, or secret-removal needs; drafts may simply be deleted.
- **Moving concepts into a newly earned area is ordinary work**, not a migration. The three-concept rule lets them wait at the root so the area's name is *observed* rather than guessed — a set cannot be named before you have seen it.

## Relationships

An optional `# Relationships` section gives selected links a stable label — one label, one target per bullet:

```markdown
# Relationships

- Superseded by: [new-term](/reporting/new-term.md)
- Refines: [parent-decision](/ways-of-working/parent-decision.md)
- Implemented by: [PR #42](https://github.com/org/repo/pull/42)
```

Core labels: Superseded by, Depends on, Constrained by, **Part of**, Refines, Specified by, Implemented by, Resolves, **Partially resolves**, **Tracked by**, Related to — each read from the containing concept outward. Use bundle-relative links (leading `/`) for internal targets. Ordinary markdown links elsewhere in the body are valid untyped edges. `sources` carries provenance; Relationships carry meaning — keep them separate.

- **`Part of`** for composition — a constituent, not a narrowing. Two buckets that sum to a balance are `Part of` it, not `Refines` and not peers. One direction only; backlinks are computed.
- **`Resolves` versus `Partially resolves`:** `Resolves` is genuine closure only. Evidence that moves an open item forward while leaving it open uses `Partially resolves`. Loose `Resolves` makes open items read as settled — the same class of error as an unearned `verified`.
- **`Tracked by`** points at the work-tracking record chasing this concept — the issue that carries who owes an open question and by when, while the question itself stays here. It is not `Specified by` or `Implemented by`, and it carries no state: openness is still read from `Resolves` / `Partially resolves`.
- **Never write the same label back.** Labels read outward, so `Refines` both ways says each concept narrows the other, and `Constrained by` both ways says a question and a rule gate each other. Backlinks are computed, never authored. `Related to` pointed back along an edge that already has a precise label is the same redundancy wearing a weaker one. Fine: `Related to` between genuine peers, and two *different* complementary labels.
- Reaching for `Related to` repeatedly means a label is missing. If it carries a large share of your edges, name the relationship instead.

## Every write updates index and log

A concept write is complete when three things exist:

1. The concept file.
2. Its area `index.md` entry — `* [Title](file.md) - description`, description copied exactly from frontmatter. **Group an area index by `type`**, definitions first, since the directory no longer carries kind; grouping headings must be reproducible from concept metadata. A concept written at the bundle root gets its entry in `knowledge/index.md` instead, and a newly created area adds its own `* [Area](area/) - <subject>` line there — the one index entry that is authored rather than copied, because a directory has no frontmatter. Above ~20 entries, group under a second axis (`tags`, or `status` for lifecycle) or nest a sub-area; beyond a few dozen, generate the index from frontmatter rather than hand-maintaining it.
3. Its `knowledge/log.md` entry — under today's `## YYYY-MM-DD` heading (newest first): `* **Creation**: …`, `* **Update**: …`, `* **Deprecation**: …`, or `* **Area created**: …` with a link. Log meaningful lifecycle events only, never formatting edits.

## Mirroring sources into `references/`

Mirror an external artifact only when a concept's `sources` needs to cite it and its external home is ephemeral — never merely because a meeting, call, or thread happened. Confirm the content may live at repository visibility before committing.

- Mirrored markdown artifacts are concepts (e.g. `type: Meeting Transcript`, registered in `types.md`) with a `sources` entry naming the original recording, thread, or document. They are immutable snapshots.
- `references/` is not an area: it is organized by source and date, is exempt from the area-naming and three-concept rules, and may nest — but a nonempty `references/` and each nonempty subdirectory still needs an `index.md`.
- Text may be mirrored in full, sanitized where confidentiality demands. Images only when cited, optimized first. Video and audio never — link them externally and mirror the transcript instead.
- Non-markdown assets under `references/` are not concepts; the concepts citing them provide their context.
- **Deciding not to mirror is also durable.** Cite the artifact as an OKF §5.1 scope descriptor in `sources[].resource` — a value the consumer cannot dereference, e.g. `Client demo recording, 30 July 2026 — retained outside this repository` — and state the reason in the body. A scope descriptor beats a path that does not resolve: it is honest about being unfollowable and mints no link a later mirroring decision must repair.

## Execution stays external

Tickets, issues, and PRs live in the issue tracker. Concepts link to them (`Specified by`, `Implemented by`) — the bundle never mirrors their state, and a linked record's status lives only in the tracker.

**"Specification" is a genre, not a location.** What makes something an execution record is that a tracker owns its state — a status, an assignee, a workflow the bundle does not advance. A spec opened as a GitHub issue is an execution record: link it, never mirror it. A spec the project maintains as durable knowledge — it outlives the work it scoped, later concepts cite it, and its only state is `status` — is a `Specification` concept, filed with its subject like anything else. Never both: one artifact, one home.

## Beyond this profile

The profile constrains a subset of OKF and leaves the rest alone. When you need something this skill doesn't cover, the answer is in [OKF-0.2.md](./OKF-0.2.md) — the pinned spec, vendored so it is readable without a network fetch. Read it and follow it; do not invent a convention, and do not assume the omission means the mechanism is unavailable.

What the profile deliberately says little or nothing about:

| Look up | OKF § |
| --- | --- |
| **Attested Computation** — `runtime`, `parameters`, `computation`, `executor`, `attester`, the `# Computation` heading, and how a consumer executes and attests | §10 |
| **`usage_count` and `usage_window`** — adoption and liveness signals on a source, and why they read as trend rather than score | §5.1 |
| **Lineage through links** — recursing into a source that is itself a concept, so credibility propagates without a `derived_from` field | §5.1 |
| **Conventional body headings** `# Schema` and `# Examples` | §4.2 |
| **`resource`** as the canonical URI of the asset a concept describes | §4.1, §6.2 |
| **Tag-based views**, synthesized at consumption time rather than stored as files | §3.1 |
| **v0.1 fallbacks** — legacy `timestamp` and body `# Citations` in inherited bundles | §13 |

Two rules govern the gap. Silence is **deference**, so a question the profile does not answer is answered upstream and following OKF there is correct, not a deviation. Silence is **not prohibition**, so a mechanism OKF permits and the profile never mentions is permitted. The profile's actual narrowings are stated as such and you have already read them: no custom frontmatter fields, no kind-named directories, `status` as knowledge lifecycle only, an `index.md` in every nonempty directory with descriptions copied verbatim.
