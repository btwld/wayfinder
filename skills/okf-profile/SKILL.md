---
name: okf-profile
description: Author and review the knowledge bundle at knowledge/ per Concepta OKF Profile 2026.2 (OKF 0.2). Use before creating, editing, deprecating, moving, or mirroring bundle content; when auditing Profile conformance or producing a Profile Review Report; or when another skill needs Profile conventions.
---

# Concepta OKF Profile

The knowledge bundle at `knowledge/` is an Open Knowledge Format (OKF) bundle following the Concepta OKF Profile — versions declared in `knowledge/profile.md`. The profile is a thin layer on **OKF 0.2**, which is authoritative: it says *which* knowledge is worth storing, *where* it goes, and *how* concepts link, and it defines no file type, no frontmatter field, and no metadata semantics of its own. Nothing here overrides the [OKF specification](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/3fcbb9f828c2f23d109c855ee403c3a4c81f3a96/okf/SPEC.md), pinned to the 0.2 commit and vendored at [OKF-0.2.md](./OKF-0.2.md).

Before applying any rule below, read the first fenced `yaml` block in
`knowledge/profile.md`. This skill implements only `concepta_profile: "2026.2"`
with `okf_version: "0.2"`. If the declaration differs, do not write, reassess,
or silently migrate the bundle under 2026.2. Report the declared release as
unsupported by this skill and ask for the matching historical skill or an
explicit whole-bundle migration. Generic OKF reading remains available.
The declaration is only a release selector: never turn `profile.md` into a
standalone definition, extension registry, second schema, or OKF override.

**Where this skill is silent, OKF 0.2 governs.** Silence means the upstream spec already settles the point, so read it and follow it — never invent a Concepta convention to fill a gap. See [Beyond this profile](#beyond-this-profile) for what that covers in practice. Within what the profile *does* specify, concepts take these shapes and never invented ones.

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
- **Earned, not predicted.** A genuine shared subject may have an area at any size; a numeric threshold cannot prove the placement. Do not create speculative areas for a taxonomy the current corpus does not demonstrate.
- **Indexed.** A nonempty area needs its own `index.md`.
- **Nestable** under the same rules, but every path segment is identity, so nest only when a subject genuinely subdivides.
- **File, don't create.** Put a new concept into an existing area or at the root. Creating an area is a deliberate act, recorded in `log.md` — the cost of a wrong area is not a wrong folder, it is a path, and a path is identity.
- **A subject concept is ordinary knowledge.** A specifically named concept may explain the area's subject when it carries durable knowledge. Never create a generic `overview.md` that merely duplicates the generated index; directory index entries have path-derived labels and no authored descriptions.

### Placement

A concept lives with its subject. A decision about billing goes in the billing area; a decision about how the team captures knowledge goes in `ways-of-working/`.

- **`architecture/` holds architecture whose subject is the system as a whole** — structure, technology, boundaries, integration contracts, and the ADRs that shaped them. Architecture whose subject is one capability lives in that capability's area: a data model for billing is billing knowledge that happens to be architectural. The type stays `Architecture Document` in both places. Placement follows subject, never type.
- **`interactions/` is the time-axis exception.** A dated record ordinarily spans several subjects, so no single area can host it. Its name matching its type is fine here and nowhere else: the axis is time, and a record spanning subjects scatters none of them. The durable-capture bar still applies — an interaction that produced one durable outcome contributes that outcome to *its* subject's area, not a record here. A thin `interactions/` is the expected shape.

Creating a bundle from nothing: [SEEDING.md](./SEEDING.md) holds the root files.

## What earns a concept

A source event is an activity: a daily, planning session, demo, call, or conversation. It **never** becomes a concept merely because it happened. An artifact the event produced, such as a transcript, may be mirrored as an ordinary source concept when the mirroring rule applies. An interpreted concept is earned when the event produced durable knowledge: a meaningful request, decision, investigation and findings, architectural constraint, term, standing rule, named unknown, or reusable guidance. An event that produced none leaves no interpreted outcome behind, and that is correct rather than a gap — the bar keeps the bundle from degenerating into routine minutes.

Requests are ordinarily first-class: a request outlives the conversation that expressed it and can later be analyzed, specified, implemented, rejected, or superseded, which is a lifecycle of its own.

**Promotion is decided by identity, not importance.** The Profile recommends promotion when an outcome needs independent status, provenance, relationships, reuse, replacement, or history; genuine boundary cases may stay embedded. Given an outcome — a decision, an answer, an unknown — ask whether it has a lifecycle outside the concept where it arose:

- **Normally keep it embedded** when it has no meaningful identity of its own. A small outcome that will never be referenced, verified, or superseded on its own can stay where it arose, as a heading in that concept's body.
- **Prefer its own concept** when it needs independent status, provenance, relationships, reuse, replacement, or history.

An ambiguous outcome should normally start embedded, because un-promoting it is free until something outside the bundle cites its path. The same test decides a `Question`: a named unknown with an evidence trail, several dependents, or an ID cited outside the bundle is normally a concept; a single unknown belonging to one concept, with nothing recorded but the gap itself, can remain a heading in that concept's body.

An **Interaction Record** is the narrower case of the same rule: write one only when an interaction's *combined* context is itself durable — several linked outcomes, a negotiation, a demo whose overall shape matters. When one outcome mattered, that outcome links straight to its external source and no record is written. Never produce one as routine minutes.

## Types

`type` is the only place kind is carried — not the directory, not the filename, not a tag. `knowledge/types.md` always retains all fourteen standard rows below, in this order and with these meanings, including unused standards. Every additional used type is registered after them in case-sensitive lexical order.

| Type | Intended content |
| --- | --- |
| `Glossary Definition` | One project or domain term |
| `Business Rule` | One standing business rule, constraint, invariant, or policy |
| `Question` | One named unknown, with what is known, what is missing, and what would close it |
| `Request` | A durable request from any relevant source |
| `Analysis` | An investigation, feasibility study, comparison, or recommendation |
| `Decision` | A durable non-architectural decision with an independent lifecycle |
| `Architecture Decision Record` | An architectural decision in ADR form |
| `Architecture Document` | A durable description of the system architecture |
| `Specification` | A specification the project maintains as durable knowledge, not one a tracker owns the state of |
| `Guide` | Durable operational or engineering guidance |
| `Interaction Record` | An interaction whose combined context is itself durable |
| `Knowledge Profile` | The Concepta Profile and OKF release declaration |
| `Type Registry` | The standard and project-specific types available to the bundle |
| `Actor Registry` | Actor IDs mapped to identity, affiliation, role, and active period |

Project-specific types are allowed and must be registered before use. A registered extension receives a non-blocking advisory so repeated needs can inform a later Profile release; it is not prohibited because a reviewer might prefer a standard type. Choosing whether a standard or project-specific type and its registered meaning truthfully fit the concept is a mandatory Profile Review judgment, never something inferred mechanically from headings, paths, or keywords. When reading, tolerate unknown types, fields, and relationship labels — valid OKF you don't recognize is content to preserve, not an OKF error, and the registry is never grounds for rejecting a concept.

- **`Business Rule` is formalism-neutral.** One standing rule per concept. Structure them with SBVR or any other notation the domain suits; the type commits to one-rule-per-concept, not to a notation.
- **`Architecture Decision Record` versus `Decision`:** use the ADR type when the decision shapes the software's structure and an engineer deciding how to build would read it; `Decision` for every other durable decision — process, commercial, scope, governance. When both fit, prefer `Decision`.
- **A `Business Rule` is not a `Decision`.** A rule describes how the business already works; a decision records a choice with alternatives.
- When a Decision selects a Business Rule, the rule should link outward to that Decision with `Depends on`.
- **A `Question` carries no state in its type or its path.** Whether it is still open is read from inbound relationships: `Resolves` means closed, `Partially resolves` means narrowed, neither means open. A resolved question stays `stable` — how understanding arrived at an answer is knowledge in its own right.
- **Splitting a concept:** the Profile recommends splitting when parts would carry materially different verification or lifecycle — frontmatter applies to the whole concept, and averaging trust across it is lossy. Mixed *provenance* is fine because footnotes handle it; mixed *verification* is the signal to consider a split. Size alone is not.

Use only the headings that help the concept. Useful compact starting shapes are:

| Type | Starting headings |
| --- | --- |
| Request | Request, Context, Constraints |
| Decision / Architecture Decision Record | Context, Decision, Consequences |
| Analysis | Question, Findings, Recommendation |
| Glossary Definition | Definition, Avoid |
| Business Rule | Rule, Rationale, Consequences |
| Question | Question, What is known, Still missing, What would close it |

These are authoring prompts, not conformance rules. Bodies remain free-form; omit,
rename, or add headings as the knowledge requires. Add `# Relationships` only when
the concept has labelled links.

## Baseline frontmatter

Every concept carries truthful, nonempty discovery and lifecycle metadata:

```yaml
---
type: <Concept type, e.g. Glossary Definition>
title: <Display name>
description: <One sentence; copied verbatim into the area index>
status: draft | stable | deprecated
---
```

- Add `generated: { by: <actor>, at: <ISO 8601 datetime> }` when the producer and meaningful-change time are known. It is recommended, not required; never fabricate either value to clear an advisory.
- **Status** is knowledge lifecycle only — `draft`, `stable`, `deprecated`. Workflow states (accepted, blocked, in progress, done) belong to the issue tracker.
- Add native OKF fields (`tags`, `resource`, `stale_after`) when their OKF-defined meaning applies. `sources` and `verified` have their own section below.
- **`tags` carry topic and nothing else** — never kind (that is `type`), lifecycle (`status`), trust (derived from `verified`), or a judgment about how settled the subject is (body prose). A tag restating one of those is redundant when written and wrong once the real signal moves: `partially-resolved` on a question is a fact about an inbound edge, and nothing updates it when a second edge lands.
- Concepta producers write only OKF-defined fields. Readers still preserve unknown fields and keep the concept loadable, because the producer restriction does not change OKF's tolerant-reader contract.

## Provenance and trust

Read OKF §5 before writing provenance or trust fields; it owns their syntax and
meaning. The Concepta delta is narrower:

- When a claim materially derives from identifiable source material, record that material with OKF `sources`; original analysis, guidance, and decisions do not invent sources just to satisfy the rule. Profile Review judges whether material provenance is missing, while tools check only present source structure and attribution joins.
- Write `generated` or `verified` only when the upstream event genuinely occurred. Editorial review, migration, or a desire to clear a check is not generation or verification.
- **Absence of `verified` is a signal, not a defect.** A concept deliberately recording unconfirmed material is *correctly* unverified. Never add a verification event to satisfy a convention, a checklist, or a linter; tooling must not report missing verification as a finding.
- **Organizational identity is not in the tier.** Trust tiers distinguish human from machine, not client from internal. That distinction lives in `knowledge/actors.md`, whose `Side` is exactly `client`, `internal`, `vendor`, `tool`, or `unknown`. Never guess an affiliation: use `unknown`. `Active` is `YYYY-MM-DD – YYYY-MM-DD` (start inclusive, end exclusive), `YYYY-MM-DD –`, or `unknown`; repeated rows for one ID must not overlap. Resolve `generated` and `verified` at their event timestamps, and a source author at `last_modified` when available; otherwise affiliation stays unknown. A third-party authoring agent is `tool`; a process the project itself runs is `internal`. Never encode affiliation into an actor ID — `human:acme/jane-doe` puts a mutable attribute inside an immutable key and forces a rewrite when it changes. Registry lookup never changes the actor string, its OKF prefix, or its derived trust tier.
- Never invent a maturity, confidence, credibility, or evidence-tier frontmatter field. Use the upstream signals and attribution mechanism without restating or extending them.

- **How settled the *subject* is belongs in the body, not in frontmatter and not in `status`.** `status` describes the document — OKF's `draft` means "not yet reviewed". State the assessment beside the reasoning that justifies it, with pointers to what would settle it; define the vocabulary once in a `ways-of-working/` concept. It is **not derivable from links**: `Constrained by` may target a fully settled constraint, broken links are valid, and absence of links is silence rather than evidence. A concept can be first-party, verified, and still describe an unsettled subject.
- **Freshness needs evidence.** Add `stale_after` only when the content has a real horizon supported by evidence, never as a default for a type or as a conformance placeholder.

## IDs and lifecycle

- A concept's ID is its path from the bundle root without `.md`: `reporting/token-contract`. Use readable lowercase kebab-case for each authored slug. Put a date in the path only when chronology is intrinsic to stable identity (for example, Interaction Records and mirrored snapshots), never for creation time, freshness, workflow, or an editable version. Status, owner, priority, and Profile version never appear in filenames.
- **An ID other systems already cite is part of identity — preserve it verbatim, leading the path.** `d11-collected-revenue-basis`, `architecture/0008-direct-token-consumption`. Requirement numbers, rule codes, question numbers, ADR sequence numbers: never renumber, never trade one for a nicer name. They are cited in trackers, matrices, client documents, and scripts that grep them, so they are already frozen by citation — the concept adopts a frozen identity rather than minting a rival.
- **A concept may move at any `status`**, for as long as every reference to it can be repaired. A move is complete in one operation: inbound bundle links repointed, affected indexes regenerated, and a `* **Move**:` entry in `log.md` naming both paths. `status` never decides this — movability is about who points at the path, not how reviewed the document is, and holding a finished concept at `draft` to keep it movable is the `status` abuse the profile forbids.
- **A path freezes when a known citation outside the bundle cannot be repaired** — a tracker issue, a client deliverable, another repo, anywhere you cannot coordinate the update. A repairable external citation does not freeze it merely by crossing the boundary. Before moving a concept carrying `Specified by`, `Tracked by`, or `Implemented by`, you should inspect the linked execution record for citations; the relationship alone is not proof. If a citation cannot be repaired, retain the path and retire by `status: deprecated` plus a `Superseded by` link when a successor exists.
- Inside the bundle a broken link is tolerated by OKF and repairable by you, which is why the freeze sits at the boundary where neither is true.
- Stable concepts normally deprecate, and link an available successor with `Superseded by`. Drafts may simply be deleted. Hard-delete stable content only for an exceptional security, privacy, legal, secret-removal, or genuinely erroneous-content reason; Profile Review must assess the reason and known citations.
- **Moving concepts into a newly justified area is ordinary work**, not a migration. The current corpus, not a count, must make the shared subject truthful.

## Relationships

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

## Every write updates index and log

A concept write is complete when three things exist:

1. The concept file.
2. Every affected `index.md` semantic projection. At root, `Bundle` contains `log.md`, `profile.md`, `types.md`, and conditional `actors.md`; other concepts group under exact types; immediate directories group under `Directories`; non-Markdown files under `references/` group under `Assets`. Standard type groups follow the Profile order and project types follow lexically; entries sort by title then path. Concept labels and descriptions copy `title` and `description`; directory and asset labels derive exactly from their final path segment and carry no description. Indexes contain no authored ordering or prose.
3. Its authored `knowledge/log.md` entry — under today's `## YYYY-MM-DD` heading (newest first): `* **Creation**: …`, `* **Update**: …`, `* **Deprecation**: …`, or another nonempty bold lead word followed by a colon. Log meaningful lifecycle events only, never formatting edits. The log is history, not a projection.

## Mirroring sources into `references/`

Mirror an external artifact only when a durable concept cites it through `sources`, its availability is genuinely at risk, and the material may live at repository visibility. A source being outside project control is evidence to consider, not enough by itself. Never mirror merely because a meeting, call, or thread happened.

- Mirrored markdown artifacts are concepts (e.g. `type: Meeting Transcript`, registered in `types.md`) with a `sources` entry naming the original recording, thread, or document. They are immutable snapshots.
- `references/` is not an area: it is organized by source and date, is exempt from subject naming, and may nest — but a nonempty `references/` and each nonempty subdirectory still needs an `index.md`.
- Text may be mirrored in full and must be sanitized where confidentiality demands. Images only when cited, optimized first. Video, audio, and other heavy binaries never — keep the followable source external and prefer an appropriate transcript when preservation is needed.
- Non-markdown assets under `references/` are not concepts; the concepts citing them provide their context.
- **Deciding not to mirror is also durable.** Preserve ordinary OKF source meaning: keep a known followable URL or path in `sources[].resource`; use a scope descriptor only when the source is inherently unfollowable. A material non-mirroring reason should be stated in the body. Never replace a followable resource with a descriptor merely to silence availability concerns.

## Execution stays external

Tickets, issues, and PRs live in the issue tracker. Concepts link to them (`Specified by`, `Implemented by`) — the bundle never mirrors their state, and a linked record's status lives only in the tracker.
One concept may link to several execution records or none; cardinality alone is
never a finding.

**"Specification" is a genre, not a location.** What makes something an execution record is that a tracker owns its state — a status, an assignee, a workflow the bundle does not advance. A spec opened as a GitHub issue is an execution record: link it, never mirror it. A spec the project maintains as durable knowledge — it outlives the work it scoped, later concepts cite it, and its only state is `status` — is a `Specification` concept, filed with its subject like anything else. Every durable specification has exactly one lifecycle owner. Never both: one artifact, one home.

## Profile Review

After a write or when asked for Profile Review, run automated validation over the
whole bundle when `okfp validate` is available, then assess every contextual rule
taught in this skill for the review scope. In a source checkout, the canonical
assignment audit is [`../../implementation/profile-coverage-2026.2.md`](../../implementation/profile-coverage-2026.2.md);
the review map below keeps a copied skill self-contained.
Routine review covers changed concepts and their directly affected placement,
indexes, relationships, and dependents. Adoption, release upgrades, migrations,
and structural reorganizations cover the whole bundle.

Use this compact review map to enumerate the contextual surface: structure and
placement (§§3, 9–10, 13); durable capture and concept boundaries (§4);
metadata, type fit, provenance, actor history, trust, lifecycle, and freshness
(§§5–6); relationship meaning, execution ownership, identity, moves, and
retirement (§§7–8); Profile declaration semantics (§11); and source mirroring
(§12). Mark a section not applicable only after checking it against the scope.

Complete the review autonomously when the required context is present and every
judgment is clear. Use `NEEDS HUMAN` for an ambiguous mandatory rule, apparent
Profile/OKF conflict, missing external context, or proposed exception. Fix clear
defects and review again. Emit this compact report in the interaction or pull
request, never as a blanket certificate inside the bundle:

```markdown
## Profile Review Report

- Profile: 2026.2 (OKF 0.2)
- Scope: <changed concepts and affected neighbors | whole bundle>
- Automated: <PASS | FAIL | UNSUPPORTED | NOT RUN — reason>
- Reviewed: <applicable Judgment Rule Profile sections, comma-separated>
- Outcome: <PASS | CHANGES REQUIRED | NEEDS HUMAN>
- Concerns: <none | compact actionable findings or uncertainty>
```

`PASS` means every Judgment Rule in scope was assessed with sufficient context;
it does not replace or reinterpret the independent OKF or automated Profile result.

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
