# Concepta OKF Profile

**Version 2026.1** — profiles **OKF 0.2 exactly**

Status: Proposed

Concepta Profile 2026.1 is the current release.

The Concepta OKF Profile is a set of conventions for keeping durable project
knowledge as an [Open Knowledge Format][okf] bundle in the same repository as the
code it describes. It is a *profile*, not a format: it defines no file type, no
frontmatter field, and no metadata semantics of its own. Every mechanism it uses
— bundles, concepts, frontmatter families, cross-links, indexes, logs — is
defined by OKF and used with its OKF meaning.

OKF is authoritative. Where this profile and OKF appear to differ, OKF wins, and
the profile is in error. What the profile contributes is narrower: **which**
knowledge is worth storing, **where** it goes, **how** concepts link to each
other and to the systems where work happens, and a **version** that tooling can
bind to.

This document specifies the profile and does not restate OKF; read it alongside
the pinned [OKF 0.2 specification][spec]. **Where this profile is silent, OKF
governs** — silence is deference to a spec that already settles the point, never an
invitation to invent a local convention (§1.3). §1.3 lists what the profile
inherits unchanged, and §14 defines conformance.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are to be interpreted
as described in RFC 2119.

Adoption planning, validator construction, migration, and tooling rollout are
out of scope here. They belong to the companion implementation guide,
`okf-implementation-guide.md`, which binds this release. Where the two appear to
differ, this document governs.

[okf]: https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing
[spec]: https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/3fcbb9f828c2f23d109c855ee403c3a4c81f3a96/okf/SPEC.md

---

## 1. Motivation

Concepta runs many codebases with many contributors, and durable project
knowledge arrives from two directions. Engineering knowledge — terminology,
architectural decisions, operational guidance — has long lived in repository
documents. Business-facing knowledge — client requests, planning outcomes, demo
feedback, investigations — lives in calls, Basecamp, WhatsApp, and meeting
transcripts, and rarely survives the system it was born in.

Without one model spanning both:

- Durable client and project context stays scattered across external systems,
  and leaves with the tool or the person.
- A request, an analysis, a decision, a specification, an issue, and an
  implementation describe one concern with no durable link between them.
- Source ceremonies get confused with the knowledge that survives them: either
  every meeting becomes a document, or nothing does.
- Document folders mix organizational and conceptual categories, so a path name
  carries no reliable meaning, and everything about one subject scatters across
  folders named after document kinds.
- Documents expose too little metadata for discovery, trust assessment, or
  graph construction.
- Repository setup, engineering skills, and agents each know a local layout
  rather than one shared, versioned standard.

A proprietary format would address none of these better than an open one, while
costing interoperability and permanent maintenance. So the profile adds
conventions to OKF instead of replacing it.

### 1.1 Goals

1. Give durable project knowledge one Git-versioned home beside the code.
2. Capture engineering and business knowledge in one model, without requiring
   every meeting, message, or transcript to become a document.
3. Establish one vocabulary and one structural model across repositories, teams,
   and agents, so a reader arriving at any Concepta repository already knows how
   the bundle is put together, even where the subjects differ.
4. Keep execution systems authoritative: work items and delivery records — issues,
   tickets, pull requests — stay in GitHub and Linear and are linked, never
   mirrored. What makes something an execution record is that a tracker owns its
   state, not the genre of document it is (§7.3).
5. Remain interoperable — a Concepta bundle MUST be readable by any OKF
   consumer with no knowledge of this profile.
6. Make conventions versioned, declared in-bundle, and mechanically checkable.

### 1.2 Non-goals

- Redefining, extending, or narrowing any OKF field's meaning.
- Ingesting source events: no transcript pipeline, outcome detection, or
  classification is specified.
- A graph database, graph API, or graph as a source of truth.
- Per-concept access control, sensitivity classification, or redaction.
- Prescribing a human review step, or forbidding agents from verifying.
- Binary lifecycle management: Git LFS, asset replication, archival guarantees.
- Prescribing how the profile is packaged or distributed.
- Naming any project's subjects. The profile fixes the structural model and the
  type vocabulary; what a project has knowledge *about* is the project's to name.

### 1.3 Inherited from OKF unchanged

The profile selects and constrains OKF; it never redefines it. Every mechanism
below keeps its OKF meaning. "Constrained" means the profile narrows *when or
how* Concepta uses it, never *what it means*.

| OKF | Mechanism | In this profile |
|-----|-----------|-----------------|
| §2 | Bundle, concept, concept ID, frontmatter, body, link, source, provenance | Inherited verbatim (§2) |
| §3 | Directory tree of markdown, domain-independent structure | Constrained: fixed bundle-root files and project directories name subjects (§3) |
| §3.1 | Reserved `index.md` / `log.md` | Inherited; usage constrained (§9, §10) |
| §4.1 | Frontmatter, required `type`, recommended `title`/`description`/`resource`/`tags`, producer extensions | Constrained for Concepta producers: `type`, `title`, `description`, and `status` are required, types are declared in-bundle, and producer-defined fields are prohibited (§5.1, §5.2) |
| §4.1 | Types are not centrally registered; consumers tolerate unknown types | Inherited: the in-bundle type registry is a producer-side declaration and never a reason to reject (§5.2, §14.2) |
| §4.2 | Free-form body, structural markdown, conventional headings, footnote attribution | Inherited: no type-specific template; optional labelled relationships remain ordinary Markdown (§5.3, §7.2) |
| §5.1 | `sources`, credibility signals, `usage_window`, per-claim footnotes | Inherited unchanged; mechanisms surfaced rather than summarized (§6.1) |
| §5.2 | `generated`, `verified` | Constrained: `generated` is recommended and must never be fabricated; `verified` records only verification that occurred, and its absence is meaningful (§6.2) |
| §5.3 | Trust tiers derived, not stored | Inherited unchanged; the actor registry makes organizational identity legible without touching tiers (§6.1.1) |
| §5.4 | `status`: `draft` / `stable` / `deprecated` | Constrained to the knowledge lifecycle of the document only; assessing the subject is body content, with no field and no derivation (§6.3, §6.3.1) |
| §5.5 | `stale_after` as an absolute date | Constrained: evidence-based, conditional (§6.4) |
| §6.1 | Markdown links, bundle-relative preferred, broken links tolerated | Inherited; labelled subset added (§7); internal links repaired on a move (§8.2) |
| §6.2 | Path-valued fields | Inherited unchanged |
| §6.3 | `references/` mirrors external material as concepts | Inherited; mirroring policy added (§12) |
| §7 | Actor convention (`producer/version`, `human:`, `process:`) | Inherited verbatim; IDs stay opaque and affiliation lives in a registry (§6.1.1) |
| §8 | Index files, `okf_version` at bundle root only | Constrained: required per nonempty directory, deterministic, grouped by type (§9) |
| §9 | Date-grouped log entries, newest first | Constrained: knowledge lifecycle events only (§10) |
| §10 | Attested Computation and its computation keys | Inherited unchanged (§1.3) |
| §11 | Tolerant-reader conformance | Inherited and reinforced (§14.2) |
| §12 | `okf_version` declaration and version semantics | Inherited; profile binds one OKF version (§15) |

**The table is not a boundary.** It enumerates the mechanisms Concepta constrains;
it does not limit what a bundle may use. Anything OKF 0.2 defines that this
document never mentions — a frontmatter key, a body convention, a structural
affordance, or a whole family such as Attested Computation — is available
unchanged and carries its OKF meaning. A producer facing a question this profile
does not answer MUST read the pinned specification and follow it, and MUST NOT mint
a Concepta convention in its place. That failure mode is the one this profile is
least able to detect, because a locally invented rule looks like a convention
rather than a divergence, and it is how a profile quietly becomes the competing
standard §1.2 forbids.

Silence is also not prohibition. Where OKF permits something and this document says
nothing, it is permitted. The narrowings are the ones stated as such — custom
frontmatter fields (§5.1), directory names (§3), `status` semantics (§6.3), index
presence and descriptions (§9) — and each is written as an explicit MUST or MUST
NOT. Absence of a rule is never one of them.

### 1.4 Prior art

The working model this profile assumes — a persistent, agent-maintained markdown
knowledge base that compounds over time, navigated through an index, historized
through a log, grounded in curated raw sources, and projected into disposable
views — is the LLM Wiki pattern described in [Andrej Karpathy's llm-wiki
note][wiki], the pattern that inspired OKF and inspires this profile alongside
it.

That note is inspiration and carries no normative weight. This profile's sole
normative upstream is OKF; its conventions are defined for OKF, not for the LLM
Wiki. The profile invents neither the format nor the pattern — it selects, binds,
and versions existing practice for Concepta projects.

[wiki]: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

---

## 2. Terminology

Terms defined in OKF §2 — **bundle**, **concept**, **concept ID**,
**frontmatter**, **body**, **link**, **source**, **provenance**, **actor**,
**credibility signal**, **trust tier** — are used with their OKF meanings
throughout. This profile adds:

- **Profile**: a versioned set of conventions layered on OKF that constrains
  usage without changing meaning. This document is one.
- **Area**: a directory holding every concept whose subject is one thing —
  a domain term, a capability, the system, the way the team works. An area is
  named after its subject and is not a nested bundle (§3.1).
- **Type**: the kind of document a concept is, carried by the OKF `type` field
  and declared in the bundle's type registry (§5.2). Kind is never carried by a
  directory name.
- **Type registry**: the root concept carrying the standard type vocabulary and
  every registered project-specific type available to the bundle (§5.2).
- **Actor registry**: the root concept mapping every actor ID used in the bundle
  to identity, affiliation, role, and active period (§6.1.1).
- **Durable knowledge**: an outcome worth preserving in the project after the
  activity that produced it has ended. The subject matter of the bundle.
- **Source event**: an activity that may produce knowledge — a call, daily,
  planning session, demo, or conversation. A source event is never itself a
  concept; an artifact it produces, such as a transcript, may be mirrored as an
  ordinary source concept under §12.
- **Execution record**: an artifact whose state a work-tracking system owns — an
  issue, ticket, or pull request, including one written as a specification.
  Execution records live outside the bundle and are linked, never mirrored
  (§7.3). A specification the project maintains as durable knowledge is not one;
  it is a `Specification` concept (§5.2).
- **Projection**: an artifact derived mechanically from concepts, discardable
  and rebuildable. Indexes, diagnostics, and graph views are projections
  (§13). The authored root log is not one (§10).
- **Mirror**: a copy of external source material committed under `references/`
  so provenance survives the external system (§12).
- **Promotion**: moving an outcome recorded inside one concept into a concept of
  its own, because it acquired an independent identity (§4.2).
- **Profiled Bundle**: an OKF bundle that selects a Concepta Profile release in
  its profile declaration and is assessed against both OKF and that release.
- **Deterministic Rule**: a profile rule whose satisfaction can be determined
  reliably from the bundle and its declared release.
- **Judgment Rule**: a profile rule that requires contextual interpretation by
  a human or agent. Assessment mode does not change the rule's normative force.
- **Automated Profile Validation**: the model-independent operation that
  preserves the independent OKF result and assesses Deterministic Rules.
- **Profile Review**: contextual assessment of Judgment Rules by a human or
  agent, separate from Automated Profile Validation.
- **Complete Profile Assessment**: the combined evidence from Automated Profile
  Validation and Profile Review used to assess all requirements of a Profiled
  Bundle.

---

## 3. Bundle structure

Profile conformance applies to a bundle, independent of its repository location
or whether a repository distributes other bundles. A Profiled Bundle MUST NOT
contain a nested bundle: directories inside its root organize concepts, they do
not subdivide distribution. Concepta adoption binds one such bundle to
`knowledge/` in the companion guide; that repository choice is not a bundle rule.

```text
<bundle>/
  index.md              # Root index (§9). Carries okf_version.
  log.md                # Root log (§10).
  profile.md            # Profile declaration (§11).
  types.md              # Type registry (§5.2).
  actors.md             # Actor registry when an OKF actor-valued field is used (§6.1.1).

  <concept>.md          # A concept whose subject has no area yet (§3.1).

  <area>/               # Area (§3.1). Mixed types, project-named.
    index.md            # The area's generated semantic index (§9).
    <concept>.md        # Every other file is an ordinary concept. None is privileged.
    <sub-area>/         # Nested areas are permitted (§3.1).
      index.md
      <concept>.md

  architecture/         # Default areas (§3.2). Created lazily.
  ways-of-working/
  interactions/         # Time-axis directory (§3.3).
  references/           # Mirrored source material (§3.4, §12).
```

Every project directory in the tree MUST name the **subject** its contents share,
not a kind of document. Kind is
carried by `type` (§5.2), so a directory named after a document kind — `decisions/`,
`analyses/`, `guides/`, `adr/` — duplicates metadata the concept already carries and
scatters one subject across many folders. The two exceptions are `interactions/` and
`references/`, whose organizing axis is time rather than subject (§3.3, §3.4).

### 3.1 Areas

An area is a directory holding every concept whose subject is one thing. Areas
obey five rules:

1. **Named after what its concepts share.** An area's name names the one subject
   common to everything inside it, in the project's own vocabulary — a capability,
   a domain, the system, the way the team works. Every concept in an area is an
   ordinary concept; none holds a privileged navigation role.

   An area name that matches one member concept's title is a signal the name is too
   narrow — named after a part of the set rather than what the set shares. Prefer
   the broader subject, and let the term keep its own concept as a peer.
2. **Mixed types.** An area holds concepts of any type. A glossary definition, the
   rules deriving it, the open questions about it, and the specification covering
   it belong in the same area, because they share a subject.
3. **Earned, not predicted.** A project-named area MAY contain any number of
   concepts when they genuinely share the subject its path names. Authors SHOULD
   NOT create speculative structure for subjects the current corpus does not
   demonstrate. Structure grows out of knowledge rather than a predicted taxonomy;
   a numeric threshold cannot establish whether a subject is genuine.
4. **Indexed.** A nonempty area MUST contain an `index.md` (§9).
5. **Nestable.** An area MAY contain sub-areas under the same five rules. Authors
   SHOULD nest only when a subject genuinely subdivides; every path segment is
   identity (§8.1), so depth multiplies the paths an external citation can freeze
   (§8.2).

An area's indexes navigate it but do not describe it (§9). An area MAY contain an
ordinary, specifically named concept with durable knowledge about its subject. It
MUST NOT contain a generic `overview.md` or other concept that merely duplicates
the generated index. Where the subject is a term the project defines, its Glossary
Definition is one ordinary concept among its peers.

**Creating an area is a deliberate act.** Agents SHOULD file a new concept into an
existing area or the parent directory unless the current corpus supports a genuine
shared subject. Area creation is recorded in `log.md` (§10). The cost of a wrong
area is not a wrong folder — every concept filed under it inherits a false claim
about its subject.

### 3.2 Default areas

Two subjects recur in every project, so the profile names them rather than leaving
each repository to invent a name. Both are created lazily and both are ordinary
areas under §3.1:

| Area | Subject |
|------|---------|
| `architecture/` | The system being built. Holds Architecture Documents and Architecture Decision Records. |
| `ways-of-working/` | How the team works: process decisions, conventions, engineering and operational guidance, and decisions about the knowledge bundle itself. |

Both are optional, created lazily, and otherwise follow §3.1. The same lazy rule
covers `interactions/` and `references/` (§3.3, §3.4): a bundle MAY omit any or
all of these four Profile-defined directories.

Architecture Decision Records live in `architecture/` because an ADR is an
architecture concept — its subject is the system, and `Architecture Decision
Record` is its type. Reading the ADR set as a set is an index filtered by type
(§13), not a directory.

`architecture/` holds architecture whose subject is **the system as a whole** —
its structure, technology, boundaries, integration contracts, and the ADRs that
shaped them. Architecture whose subject is one capability lives in that
capability's area, by §3.3: a data model for billing is billing knowledge that
happens to be architectural, and separating it from the rules and questions it
serves is the scattering §3 exists to prevent. The type stays `Architecture
Document` in both places — placement follows subject, never type.

**These two, plus `interactions/` and `references/`, are the only directory names this
profile specifies.** Every other directory name in this document, including in the
examples and in Appendix A, is illustrative — a plausible name for one project's
subject, never a name another project should adopt. Naming subjects is a non-goal
(§1.2): a profile that shipped a domain vocabulary would be prescribing what its
users have knowledge about.

### 3.3 Placement, and the time-axis exception

The placement rule is one sentence: **a concept MUST live with its subject.** A
decision about billing goes in the billing area; a decision about how the team
captures knowledge goes in `ways-of-working/`; a term, the rule deriving it, and
the question about it all sit together.

`interactions/` is the exception, and it is principled rather than convenient.
Interaction Records (§4.3) are organized by **time**: a dated record ordinarily
spans several subjects, so no single subject can host it, and §8.1 already permits
dates in paths only for Interaction Records and mirrored snapshots. `interactions/`
MAY nest by cadence or kind of interaction — `interactions/dailies/`,
`interactions/plannings/` — under §3.1 rule 5.

Its name matches its type, which §3 otherwise bans. The ban's two reasons both
fail here: the folder duplicates nothing, because time is the organizing axis and
`type` is not, and it scatters no subject, because a record that spans subjects has
no single area to be scattered from. A directory whose entire membership is one type
*by construction* is a different thing from a directory that sorts mixed knowledge
by kind. `interactions/` rather than `meetings/` because the qualifying set is
wider than ceremonies: a document markup or a message thread that produced several
linked outcomes is an Interaction Record too, and needs the same home.

The durable-capture rules still apply inside it (§4.1, §4.3): an interaction earns a
concept only when its combined context is durable, and one that produced a single
durable outcome contributes that outcome to *its* subject's area, not a record to
`interactions/`. A thin `interactions/` is the expected shape.

### 3.4 The `references/` directory

`references/` carries the OKF §6.3 convention — external material mirrored into
the bundle as first-class concepts — and is **not** an area. It is therefore exempt
from the subject-naming rule of §3.1: mirrored material is
heterogeneous, is organized by source and date rather than by subject, and MAY be
organized into subdirectories. A nonempty `references/` MUST still carry an
`index.md`, and so MUST each of its nonempty subdirectories.

A source directory MAY keep the verbatim originals it preserves in a `raw/`
subdirectory. Within `raw/` and any of its subdirectories, the only markdown
file permitted is each directory's own `index.md`: everything else in the tier
is a non-concept asset (§12) and stays byte-for-byte. A readable mirror derived
from an original is a sibling of `raw/` in its source directory, never inside
it. Because this rule keys on the name, `raw` is reserved within `references/`
and MUST NOT name a source directory. The tier belongs to a source directory
alone: `raw/` MUST NOT sit directly under `references/`, which is not a source
directory — a flat `references/` organizes into source directories before
adopting the tier.

What may be mirrored, and when, is specified in §12.

### 3.5 Root files

A bundle MUST contain `index.md`, `log.md`, `profile.md`, and `types.md` at its
root. `actors.md` is conditional. A bundle MUST NOT use any of these names for
another purpose:

| File | Purpose |
|------|---------|
| `index.md` | Root index; carries `okf_version` (§9). Reserved by OKF §3.1. |
| `log.md` | Root log (§10). Reserved by OKF §3.1. |
| `profile.md` | Profile declaration (§11). An ordinary concept. |
| `types.md` | Type registry (§5.2). An ordinary concept. |
| `actors.md` | Actor registry (§6.1.1). Required when any concept uses an OKF actor-valued field; otherwise optional. An ordinary concept. |

`profile.md`, `types.md`, and optional `actors.md` are concepts, so a bundle
carrying them stays plainly OKF-conformant (OKF §3.1, §11): each has frontmatter
and a `type`, and a consumer that knows nothing of this profile reads ordinary
documents.

Concepts other than these MAY sit at the root. Every other `.md` file in the tree
is a concept.

---

## 4. Durable capture

The profile governs stored knowledge, not event ingestion. This section is what
keeps a bundle from degenerating into a meeting archive.

### 4.1 What earns a concept

A source event is only an activity. A daily, planning session, demo, call, or
conversation MUST NOT become a concept merely because it occurred. Authors MUST
use the durable-knowledge test below rather than event occurrence to decide whether
to create a concept; Profile Review assesses that contextual judgment (§14.1).

A concept is created when a source event produces durable knowledge worth
preserving: a meaningful request, a decision, an investigation and its findings,
an architectural constraint, a term, a standing rule, a named unknown, or reusable
guidance. A source event that produces none leaves nothing behind, and that is a
correct outcome, not a gap.

Requests are ordinarily first-class concepts. A request outlives the interaction
that expressed it and can later be analyzed, specified, implemented, rejected,
superseded, or revisited — a lifecycle of its own, which is exactly what earns a
concept.

### 4.2 The promotion rule

Decisions, answers, questions, and other outcomes are placed by **identity**,
not by importance:

An outcome SHOULD be promoted to its own concept when it needs independent status,
provenance, relationships, reuse, replacement, or history. When it has no meaningful
identity or lifecycle outside an existing concept, keeping it embedded is valid.

A small outcome that will never be referenced, verified, or superseded on its
own SHOULD stay where it arose. Promotion is reversible until something outside
the bundle cites the new path (§8.2), so a genuinely ambiguous outcome SHOULD start
embedded.

The same test decides an open question. A named unknown with an evidence trail,
several dependents, or an ID cited outside the bundle is a concept of type
`Question`. A single unknown belonging to one concept, with nothing recorded about
it but the gap itself, is a heading in that concept's body.

### 4.2.1 The inverse: when to split a concept

Promotion moves an outcome *out of* a concept. The opposite pressure arises as a
concept grows, and it has a different trigger.

A concept SHOULD be split when parts of it would carry materially different
**verification** or **lifecycle**. Frontmatter applies to the whole concept: one
`verified` history and one `status`. A concept holding
both confirmed and unconfirmed material cannot express that difference in frontmatter,
and averaging it is lossy in the one direction that matters — the unconfirmed parts
inherit the confidence of the confirmed ones.

Per-claim **provenance** does have a mechanism: footnotes keyed to a `sources[].id`
(§6.1). Per-claim **verification** does not. So mixed provenance inside one concept is
workable, and mixed verification is the signal to split.

Size alone is not a reason to split, and neither is heading count.

### 4.3 Interaction Records

An Interaction Record is optional and MAY be created when an interaction's
*combined* context is itself durable — several linked outcomes, a negotiation,
a demo whose overall shape matters. It MUST NOT be created when that combined
context is not independently durable.

When only one outcome matters, that outcome SHOULD link directly to its original
external source, and no Interaction Record is required. An Interaction Record
MUST NOT be produced as routine minutes.

Interaction Records live in `interactions/` (§3.3).

---

## 5. Concept documents

Every concept is an OKF concept document (OKF §4): UTF-8 markdown, YAML
frontmatter, free-form body.

### 5.1 Baseline frontmatter

The profile introduces **no** frontmatter fields. Every key used is defined by
OKF, with its OKF meaning.

A concept MUST carry nonempty `type`, `title`, `description`, and `status` fields:

```yaml
---
type: <Concept type>
title: <Human-readable display name>
description: <One sentence summarizing the concept>
status: draft | stable | deprecated
---
```

Only `type` is required for OKF conformance (OKF §4.1). The other three are
additional producer requirements of this Profile: `title` and `description` make
identity and discovery legible without opening the body, `description` supplies
the index projection (§9), and explicit `status` prevents OKF's absent-means-stable
default from misrepresenting a draft. Authors MUST choose truthful values; Profile
Review assesses semantic accuracy while Automated Profile Validation checks the
fields' presence, shape, and permitted `status` value (§14.1).

`generated` SHOULD record how the current content was produced. Its absence is an
advisory, never a failure, and an author or tool MUST NOT fabricate generation
provenance to satisfy the recommendation (§6.2).

The optional OKF fields `resource`, `tags`, `sources`, `verified`, and
`stale_after` remain available with their OKF-defined meanings. Sections §5.1 and
§6 state the Profile's specific producer rules for using them.
Concepta producers MUST NOT introduce namespaced or otherwise producer-defined
frontmatter fields. This constrains what Concepta writes; it does not change OKF's
tolerant-reader contract. Consumers MUST NOT reject a document for an unknown field
and SHOULD preserve unknown keys when round-tripping, exactly as OKF requires
(OKF §4.1, §11; §14.2).
Establishing conventions before extending the schema keeps the profile
interoperable by construction.

**`tags` carry topic, and nothing else.** A tag groups concepts by what they are
about — a domain, capability, or theme a reader might sweep for. A tag MUST NOT
exactly repeat the concept's `type`, `status`, derived trust tier, or a standard
relationship label. A tag also MUST NOT serve as a semantic alias for kind,
lifecycle, trust, or how settled the subject is. Automated Profile Validation
checks exact duplication; Profile Review assesses semantic aliases (§14.1). Each
of those meanings has a field or mechanism that a consumer reads, and a tag is either
redundant on the day it is written or wrong on the day the real signal changes —
`partially-resolved` on a question is a fact about an inbound `Partially resolves`
edge, and nothing updates it when a second edge lands. The prohibition is the same
one §5.2, §6.3, and §6.3.1 each make for their own field, stated once for the field
that has no meaning of its own to defend it.

### 5.2 Types and the type registry

`type` carries the kind of document a concept is, and it is the **only** place kind
is carried: not the directory (§3), not the filename, not a tag.

A bundle MUST contain a **type registry** at `types.md`, an ordinary concept of
`type: Type Registry`. It MUST contain all fourteen standard types below in this
canonical order and with these exact meanings, including standards the bundle does
not yet use. Every used type MUST resolve there. Projects MAY add project-specific
types. When present, their rows MUST follow all standard rows in
case-sensitive lexical order and MUST carry a truthful one-line meaning. A
registered project-specific type is conformant and produces a
non-blocking advisory so recurring extensions can inform a later Profile release.
The registry is what makes the invented-type failure visible: without it, kind is
unconstrained free text and `Buisness Rule` reads as a new kind of thing.

The standard vocabulary:

| Type | Intended content |
|------|------------------|
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

Project-specific types MUST be added to the registry before use. A locally
useful type MAY be promoted into a later profile release. A concept using a standard
type MUST match that type's intended meaning; this is a mandatory Judgment Rule
assessed by Profile Review, not a deterministic inference from headings, paths, or
body vocabulary. Consumers MUST tolerate
types they do not recognize (OKF §11, §14.2): the registry is a producer-side
declaration for the bundle's own tooling and is never grounds for rejecting a
concept, a bundle, or a type the registry does not list.

Three boundaries are worth stating, because each was routinely blurred before it
was written down:

- **A `Business Rule` is not a `Decision`.** A rule describes how the business
  already works and nobody chose it; a decision records a choice with alternatives.
  A rule that turns out to be a policy someone selected is a Decision, and the rule
  concept SHOULD link to it with `Depends on`.
- **An `Architecture Decision Record` is not a `Decision`.** Use `Architecture
  Decision Record` when the decision shapes the software's structure and an engineer
  deciding how to build would want to read it; use `Decision` for every other
  durable decision — process, commercial, scope, sequencing, or governance. When a
  decision plausibly fits both, prefer `Decision`, so the ADR set stays readable as
  the architecture record it is.
- **A `Specification` is not an execution record.** "Specification" names a genre of
  document, and a genre cannot decide where something lives. What decides it is which
  system owns the artifact's state. A spec filed as a GitHub issue has a status, an
  assignee, and a tracker lifecycle: it is an execution record, it is linked with
  `Specified by`, and §7.3 forbids mirroring it. A spec the project maintains as
  durable knowledge — one that outlives the work it scoped, that later concepts cite,
  and whose state is nothing but `status` — is a `Specification` concept, and it lives
  in the area of its subject like any other concept (§3.3). The same words can be
  either; what they may never be is both at once, because two homes for one artifact
  is the drift a bundle exists to end (§7.3).

`Business Rule` is deliberately formalism-neutral. A project MAY structure rule
concepts using SBVR — vocabulary, fact types, and definitional, derivation, and
behavioral rule classes — or any other notation that suits its domain. The type
commits to *one standing rule per concept*, not to a particular way of writing one.

`Question` carries no state in its type or its path. Whether a question is still
open is read from inbound relationships (§7.2): a `Resolves` edge means closed, a
`Partially resolves` edge means narrowed, neither means open. A resolved question
stays `stable` rather than becoming `deprecated` — how understanding arrived at an
answer is knowledge in its own right.

### 5.3 Body conventions

Bodies remain free-form, as OKF permits. The Profile defines no type-specific body
template and missing headings are not a conformance finding. Compact authoring
templates belong to the Profile skill, where they can help writers without becoming
bundle rules. Of the body, only an optional `# Relationships` section (§7.2)
carries Profile-specific machine meaning when present.

### 5.4 Example

```markdown
---
type: Request
title: Include PDF annotations in the export
description: Client asks that reviewer annotations survive the PDF export.
status: stable
generated: { by: claude-code/opus-5, at: 2026-07-30T16:20:00Z }
verified: { by: human:chris, at: 2026-07-31T09:00:00Z }
tags: [reporting, export]
sources:
  - id: demo-0730
    resource: /references/2026-07-30-reporting-demo-transcript.md
    title: Reporting demo transcript, 30 July 2026
    author: process:meeting-transcription
    last_modified: 2026-07-30
---

# Request

Reviewer annotations must appear in the exported PDF, positioned as they are
on screen.[^demo-0730]

# Context

Raised during the reporting demo while reviewing a draft export. Reviewers
currently re-enter annotations by hand after export.

# Constraints

Export must stay within the existing generation budget.

# Relationships

- Specified by: [Annotation export spec](https://github.com/conceptadev/example/issues/128)

[^demo-0730]: Reporting demo transcript, 30 July 2026
```

---

## 6. Provenance, trust, and lifecycle

The OKF frontmatter families (OKF §5) are used with their upstream semantics.
This section states only *when* Concepta applies them.

### 6.1 Provenance: `sources`

`sources` owns provenance. A concept that materially derives a claim from
identifiable source material MUST record that material with OKF `sources`, whether
it is external (a call recording, thread, or document) or internal (a mirrored
artifact under `references/` or another concept). Profile Review assesses whether
material provenance is missing; deterministic checks assess only the structure of
present entries and attribution joins. Original analysis, guidance, and decisions
MUST NOT invent sources merely to satisfy this rule.

When `sources` is present, every entry MUST carry the `resource` OKF requires.
Within one concept, each present `sources[].id` MUST be unique. A body footnote is
recognized as source attribution only when its label exactly matches one of those
IDs; ordinary Markdown footnotes remain ordinary body content and need not resolve
to `sources`. Deterministic checks can verify unique IDs and the recognized joins,
but Profile Review assesses whether a materially derived claim is missing
attribution or uses an ordinary footnote where source attribution was intended.

OKF §5 is required reading. The four mechanisms most often missed:

- **`sources[].author` is an authority signal**, written in the actor convention
  (OKF §7). It records who produced the *source*, which is a different question from
  who wrote the concept (`generated.by`) or who confirmed it (`verified`).
- **`sources[].resource` may be a scope descriptor**, not only a followable artifact.
  OKF §5.1 permits a population or scope description a consumer cannot dereference —
  useful when material is deliberately not mirrored (§12). A top-level `resource` has
  no such exemption and stays a path (OKF §6.2).
- **Per-claim attribution** uses footnotes keyed to a `sources[].id`, so one concept
  can carry claims of differing provenance without splitting (§4.2.1).
- **Credibility is inferred, never stored.** OKF records objective per-source signals
  — `author`, `usage_count` over a `usage_window`, `last_modified` — and leaves the
  judgment to the consumer, because a stored score is subjective, unportable, and goes
  stale. The profile adds no scoring, and producers MUST NOT add a confidence,
  credibility, maturity, or evidence-tier field of their own (§5.1).

### 6.1.1 The actor registry

Trust tiers distinguish **human from machine** (OKF §5.3). Most projects also need
to distinguish **whose assertion this is** — client or internal, first-party or
derived — and OKF provides no mechanism for it: a client's operations lead and an
internal analyst both derive as *human-reviewed*, collapsing exactly the
distinction an evidence model rests on.

A bundle MUST carry an **actor registry** at root `actors.md` whenever any concept
uses an actor identifier in `generated.by`, `verified[].by`, or
`sources[].author`. An actor-free bundle MAY omit it. The registry is an ordinary
concept of `type: Actor Registry` and maps every actor ID the bundle uses to its
identity, affiliation, role, and active period.

```markdown
| Actor ID | Name | Organization | Side | Role | Active |
|----------|------|--------------|------|------|--------|
| `human:chris` | Christiano Higuto | Concepta | internal | Engineering lead | 2026-01-01 – |
| `human:d-okonkwo` | Dara Okonkwo | Northwind | client | Operations authority | 2026-05-01 – |
| `claude-code/opus-5` | Claude Code | Anthropic | tool | Authoring agent | 2026-06-01 – |
```

`Side` MUST be exactly one of `client`, `internal`, `vendor`, `tool`, or `unknown`.
Authors MUST use `unknown` rather than infer an affiliation without evidence.
`tool` marks an
actor that is not a party to the work at all — a third-party authoring agent, say —
and it is distinct from `vendor` because a vendor makes assertions and a tool does
not. An automated process the project itself runs is `internal`, not `tool`: its
output is the project's own assertion.

The `Active` range is what makes the registry strictly better than encoding
affiliation in the ID. It MUST be `YYYY-MM-DD – YYYY-MM-DD` with the start inclusive
and end exclusive, `YYYY-MM-DD –` for an open-ended period, or `unknown` when no
reliable period is known. One actor ID MAY have multiple rows when identity,
organization, side, or role changes, but its dated periods MUST NOT overlap.

The table MUST have exactly the columns `Actor ID`, `Name`, `Organization`,
`Side`, `Role`, and `Active`, in that order. The type registry at root `types.md`
likewise MUST use exactly `Type` and `Intended content`, in that order. These
tables remain ordinary body Markdown and add no OKF frontmatter or graph meaning.

Three rules follow:

- **Actor IDs stay opaque.** Affiliation MUST NOT be encoded into an actor ID —
  `human:northwind/d-okonkwo` places a mutable attribute inside an immutable key
  (§8.2), forces a rewrite of every `generated.by`, `verified[].by`, and
  `sources[].author` that cites it when affiliation changes, and still means nothing
  to a consumer without a registry to interpret it. Organizational namespacing of
  actor IDs, if it is ever right, belongs upstream in OKF §7.
- **Every used actor is represented.** When the registry is required, it MUST
  contain every actor ID used by the bundle. A generic consumer encountering a
  missing row MUST still treat the organization as unknown and read the concept,
  and field; the missing row is a Profile failure and never changes
  the independent OKF result (§14.1).
- **Affiliation is looked up at event time.** For `generated.by` and
  `verified[].by`, consumers use the row active at the event timestamp. For
  `sources[].author`, they use the row active on `sources[].last_modified` when
  that date is available. Without a reliable date, or when no single row applies,
  organizational affiliation remains `unknown`.
  Ambiguity never changes or invalidates the OKF actor string or the trust tier OKF
  derives from its prefix. Automated Profile Validation checks period syntax and
  overlap but MUST NOT report unresolved affiliation as a finding; Profile Review
  assesses whether identity, affiliation, role, and periods are truthful (§14.1).
- **The registry is a lookup, not an edge.** OKF's trust fields take actor strings,
  not paths, so no link exists from a concept to an actor and none SHOULD be authored
  to simulate one. Registry rows add no nodes or edges to the OKF graph (§13).

What the registry enables is a **derived** answer to the organizational question:
which concepts rest only on internal assertion, which areas carry no client-authored
source. That is a projection (§13), computed at read time and never stored — the same
discipline OKF applies to credibility.

### 6.2 Trust: `generated` and `verified`

`generated` records how the current content was produced and is recommended as
§5.1 states. A missing `generated` field produces only an advisory. It MUST NOT
be invented by an author or tool when the producer or meaningful-change time is
unknown.

`verified` records a verification event only when its named actor genuinely
confirmed the content against its sources or `resource`, as OKF §5.2 defines.
Authors MUST NOT add an event for review, migration, or conformance work that did
not perform that confirmation. A verifier MAY be a person, agent, or process;
the actor prefix, not registry affiliation, determines the OKF trust tier.

**Absence of `verified` is a signal, not a defect.** OKF §5 is explicit that
absence carries meaning and that an unverified concept is never rejected, and
§5.3 makes *unverified* a first-class tier. A concept that deliberately records
unconfirmed material — an assumption, an internal reading, a claim awaiting
external validation — is **correctly** unverified, and its lack of a `verified`
event MUST NOT be reported as a deviation (§14.1).

A `verified` event is written when a named actor genuinely confirmed the content
against its sources, and at no other time: where a project expresses "not yet
confirmed by X" as the absence of an entry from X, any convention that pressures an
author to fill the field converts unconfirmed material into apparent sign-off.

### 6.3 Lifecycle: `status`

`status` uses the OKF values `draft`, `stable`, and `deprecated`, and expresses
the **knowledge** lifecycle only. It sits in the baseline (§5.1) because an omitted
`status` reads as `stable` (OKF §5.4), so a draft that leaves it out misrepresents
itself.

Workflow states — accepted, blocked, in progress, done, shipped — MUST NOT be
encoded in `status`. They describe execution, and execution state belongs to the
tracker (§7.3). Owner and due date are execution state by the same reasoning. Which
*party* is able to answer a question is durable knowledge and MAY stay in the body;
which person owes it by when is the tracker's.

`status` likewise does not govern whether a concept may move. Path stability keys off
external citation, not review state (§8.2), so a finished concept is never held at
`draft` to keep it movable.

`status` describes the **document**, not the subject it describes. OKF's `draft`
means "not yet reviewed; possibly incomplete" — a statement about the record. A
well-written, reviewed, `stable` concept can perfectly describe a subject that is
itself only partly settled, and a `draft` concept can describe something fully
settled. Do not stretch `status` to carry how settled the subject matter is; see
§6.3.1.

### 6.3.1 Assessing how settled the subject is

Projects often need to say how settled the **subject** is — whether the business
behaviour, design, or decision a concept describes is fully pinned down, and what
would pin it down. The profile defines no mechanism for this, deliberately.

Such an assessment belongs in the **body**, stated next to the reasoning that
justifies it and the pointers to whatever would settle it. A project MAY adopt a
vocabulary for it and SHOULD define that vocabulary once, in a `ways-of-working/`
concept, rather than leaving each author to invent one.

It MUST NOT go in frontmatter (§5.1). OKF's reasons for refusing to store a
credibility verdict apply here unchanged: such a judgment is subjective, unportable
between consumers, and goes stale (OKF §5.1). An assessment separated from its
reasoning is the thing that rots; written beside its evidence, it does not.

**Nor is it derivable from links.** `Constrained by` edges toward open items are
useful navigation — a reader following one finds what is missing — but they encode no
assessment: the label means the target limits this concept, which a fully settled
constraint also does, and a link MAY be knowledge not yet written (§7.1). Absence of
such edges is silence, not evidence, and cannot distinguish a settled subject from an
unexamined one. `verified` differs only because OKF §5.3 *defines* its absence as
meaningful. OKF §11 points the same way: derive trust tiers and staleness "only from
the fields specified here" — from specified fields, not from graph shape.

Assessment and trust are independent axes, and conflating them is the common error: a
concept can be first-party, verified, and still describe a subject whose detail is
unsettled.

### 6.4 Freshness: `stale_after`

`stale_after` is evidence-based and conditional: a concept MUST use it only when
the content has a real freshness horizon supported by evidence, and MUST NOT use
an arbitrary expiry as a type default or conformance placeholder.

Type alone neither supplies nor rules out that evidence. The same type may describe
a time-bounded present condition or an enduring historical fact; the content and
its sources decide whether `stale_after` is truthful.

---

## 7. Cross-linking and relationships

### 7.1 Links

Links between concepts follow OKF §6.1. Bundle-relative links (a leading `/`)
SHOULD be preferred for internal targets, because they survive document moves
within a subdirectory. An internal link whose target is absent MAY remain in a
conformant bundle and MAY represent knowledge not yet written. It is a
non-blocking advisory; Profile Review decides whether it is a useful planned edge
or a repairable mistake in context.

Provenance and navigation stay separate mechanisms: `sources` records where
content came from, links record how a reader traverses the knowledge.

### 7.2 The Relationships section

A concept MAY carry a `# Relationships` section giving selected links a stable
semantic label. Each bullet MUST carry exactly one label and one target:

```markdown
# Relationships

- Superseded by: [Token contract](/architecture/token-contract.md)
- Depends on: [Offline mode decision](/architecture/support-offline-mode.md)
- Implemented by: [PR #142](https://github.com/conceptadev/example/pull/142)
```

The preferred, extensible labels are:

| Label | Meaning, read from the containing concept outward |
|-------|---------------------------------------------------|
| Superseded by | This concept has been replaced by the target |
| Depends on | This concept is only valid while the target holds |
| Constrained by | The target limits what this concept may do |
| Part of | This concept is a constituent of the target, which is incomplete without it |
| Refines | This concept narrows or sharpens the target |
| Specified by | The target is the specification of this concept |
| Implemented by | The target is the work that delivers this concept |
| Resolves | This concept fully answers or closes the target |
| Partially resolves | This concept answers part of the target, which remains open |
| Tracked by | The target is the work-tracking record that chases this concept |
| Related to | An unlabelled association worth surfacing |

`Part of` is written in one direction only. Backlinks are computed, never authored
(§13), so a reciprocal "composed of" label would be redundant. Use it where a
concept is a constituent rather than a narrowing: two buckets that sum to a balance
are `Part of` it, not `Refines` of it and not peers of it.

`Tracked by` names the edge every project was reaching for `Related to` to express: an
open item lives in the bundle as knowledge, while who owes it and by when lives in the
tracker (§6.3, §7.3), and the two need a link. It is neither `Specified by` nor
`Implemented by` — a question is not specified or implemented by the issue chasing it —
and it carries no state: whether the item is still open is read from inbound `Resolves`
and `Partially resolves` edges (§5.2), never from the tracker record's status.

`Resolves` and `Partially resolves` are distinguished because most evidence narrows
an open item without closing it. Reserve `Resolves` for genuine closure; a source
that moves a question forward while leaving it open uses `Partially resolves`. Using
`Resolves` loosely makes open items read as settled. Together they are how a
`Question`'s openness is read (§5.2), which is why the distinction is load-bearing
rather than stylistic.

Reaching for `Related to` repeatedly signals a missing label. A project finding it on
a large share of its edges is better served naming the relationship — with a
project-specific label, or by proposing one for a later profile release.

Projects MAY use additional labels. A project using one SHOULD define its meaning
once in a durable `Guide` concept so authors apply it consistently. A nonstandard
label is only a non-blocking advisory. Profile Review assesses whether the label and
target express the intended relationship. Consumers MUST tolerate labels they do not
recognize. Markdown links elsewhere in the body remain valid untyped edges; labelling
adds body context, not a link requirement or a new graph type.

A Profiled Bundle MUST NOT encode relationship labels or targets in
producer-defined frontmatter. The Profile defines no relationship schema beyond
ordinary Markdown body links.

### 7.3 Execution records

Execution systems stay authoritative and external. GitHub issues and pull
requests, and Linear records, are linked from concepts — with `Specified by`,
`Implemented by`, or `Tracked by` (§7.2) — and MUST NOT be mirrored into the
bundle. Their state is read from the tracker, never copied into frontmatter or body.

**The test is state ownership, not document genre.** An artifact is an execution
record when a tracker owns its lifecycle — it has a status, an assignee, a
workflow that something other than this bundle advances. That test is what the
rule turns on, and calling a document a specification decides nothing: a spec
opened as a GitHub issue is an execution record and MUST NOT be mirrored, while a
spec the project maintains as durable knowledge is a `Specification` concept
(§5.2) and belongs in the bundle, filed with its subject (§3.3).

Two consequences follow, and they are the point of drawing the line here rather
than at the word:

- **One artifact, one home.** A specification MUST NOT exist as both a tracker
  record and a bundle concept. Copying a tracker spec into the bundle creates the
  two-sources-of-truth drift §1 opens with; promoting one is a move, not a fork,
  and the tracker record is then closed with a pointer rather than left running.
- **Neither direction is the default.** A specification written to scope one piece
  of work, whose value ends when the work ships, belongs in the tracker. One that
  outlives the work, that later concepts cite, and whose only state is `status`
  belongs in the bundle. Most projects have both, and the choice is made per
  artifact.

Every durable specification MUST therefore have exactly one authoritative
lifecycle owner: either the tracker owns its execution workflow, or the bundle
owns its OKF document lifecycle. A link between the two systems preserves
traceability; copied state does not share ownership.

One concept MAY accumulate several execution records over time, and a concept
MAY never produce any. Neither is an inconsistency.

---

## 8. Identity and lifecycle

### 8.1 Concept IDs

A concept's ID is its path relative to the bundle root with `.md` removed (OKF
§2). IDs are therefore paths, and path choices are identity choices.

The authored slug portion of a concept path MUST use readable lowercase
kebab-case; an externally cited identifier that leads it retains its exact spelling
and case. A date MUST appear only
where chronology is intrinsic to the subject's stable identity — for example, an
Interaction Record or a mirrored source snapshot — and MUST NOT encode mere
creation time, freshness, workflow state, or an editable version. Status, owner,
priority, and Profile version MUST NOT appear in a filename; they are mutable
metadata and would make identity churn.

**An identifier other systems already cite is part of identity and MUST be preserved
verbatim.** Where a project carries its own IDs — requirement numbers, rule codes,
question numbers, ADR sequence numbers — the concept's path leads with the ID and
follows it with a readable slug: `d11-collected-revenue-basis`,
`architecture/0008-direct-token-consumption`. Never renumber, and never drop the ID in
favour of a nicer name. This is not a filing convention but the §8.2 rule seen from
the other side: those IDs are cited in trackers, traceability matrices, client
documents, and scripts that parse them out of markdown, so they are already frozen by
citation, and the concept adopts a frozen identity rather than minting a competing
one. It is also why an ID that is *only* a status or a priority stays out — those
churn, which is what makes them metadata rather than identity.

Example IDs:

- `reporting/annotation` — a term, one concept among the area's peers
- `reporting/include-pdf-annotations`
- `reporting/pdf-export-feasibility`
- `reporting/annotation-types-in-scope`
- `architecture/0008-direct-token-consumption`
- `ways-of-working/evidence-and-provenance`
- `interactions/2026-07-30-reporting-demo`
- `references/2026-07-30-reporting-demo-transcript`

### 8.2 Moving a concept

A concept's path MAY change for as long as every known citation to it can be repaired.
A move is complete when three things hold, in one operation:

1. Every known inbound link inside the bundle points at the new path.
2. Every affected index entry is regenerated (§9).
3. `log.md` records the move (§10).

A move that leaves a known inbound internal link unchanged is incomplete. The
unresolved edge remains loadable and advisory under §7.1; it does not become an OKF
or Profile conformance failure merely because it reveals unfinished move work.

**`status` does not enter into it.** Movability is a property of who is pointing at
the path, never of how reviewed the document is. A rule that froze paths at `stable`
would pressure authors to hold finished concepts at `draft` to keep them movable,
which is exactly the stretching of `status` §6.3 forbids — a profile corrupting the
one field OKF defines precisely in order to protect an identity OKF does not treat as
fixed.

A concept MAY therefore move at any `status` when §8.2's citation and coordinated-
update conditions hold.

**A path freezes when a known citation outside the bundle cannot be repaired.** A
tracker issue, a client deliverable, a published document, another repository —
wherever the project cannot coordinate the citation. From that point the path MUST
NOT change; retire the concept by deprecation with a successor (§8.3) instead. An
external citation the project can update does not freeze identity merely because it
crosses the bundle boundary.

That is the only line worth drawing, because it is the only place where repair is
impossible. Inside the bundle, OKF already tolerates a broken link — it is a link,
not a malformed document, and §11 forbids rejecting a bundle for one (OKF §6.1,
§11) — so a profile that froze internal identity would be stricter than its own
normative upstream against a failure that upstream declined to treat as fatal.
Outside the bundle there is no tolerant reader on the other end, and that asymmetry
is real rather than stipulated.

A concept carrying `Specified by`, `Tracked by`, or `Implemented by` toward an
execution record (§7.3) SHOULD be reviewed for external citations before a move;
the relationship alone does not prove that its path is frozen.

This is also why §3.1 grows areas rather than predicting them — but not because a
move is expensive, since by the rule above it is cheap. An area name is a claim
about the subject its contents share, and the current corpus must support that
claim. Counting concepts cannot establish it.

### 8.3 Deprecation and deletion

The normal retirement path for a stable concept SHOULD be deprecation, not
deletion: set `status: deprecated`. Where a successor exists, the deprecated
concept MUST link it with `Superseded by`. Historical meaning stays inspectable.

Draft concepts MAY be deleted outright. A stable concept MAY be hard-deleted only
for an exceptional security, privacy, legal, secret-removal, or genuinely erroneous-
content reason that outweighs historical preservation. Profile Review MUST assess
that exception and the treatment of known citations and successors; deletion cannot
be inferred safely from final bundle state alone.

---

## 9. Index files

Index files follow the OKF index format (OKF §8) exactly: no frontmatter, except
that the bundle-root `index.md` MAY carry `okf_version`.

A nonempty directory MUST contain an `index.md`, including every area, sub-area,
`references/`, and nonempty subdirectory of `references/`. Indexes are what make a
bundle navigable without reading it, so an agent reaches the root index, then a
directory index, then a concept.

Every index MUST be the deterministic semantic projection of its directory defined
below. Conformance compares the parsed groups, membership, order, labels, targets,
and descriptions; harmless Markdown presentation differences do not affect it.
An index MUST NOT carry authored ordering, directory descriptions, or other unique
knowledge.

The projection includes immediate children only and omits the index itself:

1. At the root, `log.md`, `profile.md`, `types.md`, and `actors.md` when present
   form `Bundle`, in that order. `log.md` has the fixed label `Knowledge Log` and
   no description; concept labels are their `title` and their descriptions are
   copied exactly from frontmatter.
2. Every other concept is grouped under its exact `type`. Standard type groups
   follow the canonical order in §5.2. Registered project-specific type groups
   follow afterward in case-sensitive lexical order; an unregistered used type
   also sorts there so the projection remains reproducible while that separate
   registry defect is repaired.
3. Immediate subdirectories form `Directories`. Each label is the final path
   segment exactly as written, each target is the relative directory path with a
   trailing slash, and directory entries carry no description.
4. An immediate non-Markdown file under `references/` or one of its descendants
   forms `Assets`. Its label is its filename exactly as written, its target is the
   relative file path, and it carries no description. Other non-Markdown files are
   outside this Profile projection.

Empty groups MUST be omitted. Present groups MUST appear in this order: `Bundle`
when applicable, type groups, `Directories`, then `Assets`. Within each type group,
entries MUST sort by `title` and then target path, both case-sensitive. Directory
and asset entries MUST sort by target path. Every target MUST be relative to the
index containing it.

A target is written as a relative URL (OKF §8): a character a plain Markdown link
destination cannot carry literally — a space, a parenthesis, a character outside
ASCII — MUST be percent-encoded (RFC 3986) or carried by the angle-bracket
destination form (CommonMark). Conformance compares each target percent-decoded
against the projected path, so every valid spelling of the same target matches
the projection; a percent sign outside a valid escape sequence does not parse as
a target. Labels are not URLs and stay verbatim — an asset's label is its
filename exactly as written even when its target is encoded.

The root index MUST carry `okf_version`, which §11 requires to agree with the
profile declaration. A complete root index therefore covers the root log, the two
required root registry/declaration concepts, conditional actor registry, every
other root concept, and every immediate directory.

```markdown
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
* [Concepta OKF Profile](profile.md) - Declares the Concepta profile and OKF versions this bundle follows.
* [Types](types.md) - The standard and project-specific types available to this bundle.
* [Actors](actors.md) - Actor IDs mapped to identity, affiliation, role, and active period.

# Analysis

* [Retention window](retention-window.md) - How long generated exports are kept before deletion.

# Directories

* [references](references/)
* [reporting](reporting/)
```

An area index uses the same projection. Exact registered type names are headings:

```markdown
# Glossary Definition

* [Annotation](annotation.md) - A reviewer comment anchored to a region of a rendered report.
* [Export profile](export-profile.md) - The named settings bundle an export is rendered under.

# Business Rule

* [Annotations are immutable once exported](annotations-immutable-once-exported.md) - An exported annotation is never edited in place.

# Question

* [Annotation types in scope](annotation-types-in-scope.md) - Which annotation kinds must survive the PDF export.

# Request

* [Include PDF annotations in the export](include-pdf-annotations.md) - Client asks that reviewer annotations survive the PDF export.
```

The verbatim-description rule deliberately tightens OKF §8's SHOULD to a MUST.
Together with derived membership, grouping, ordering, labels, and targets, it makes
an index mechanically checkable and safely regenerable without a second source of
truth.

---

## 10. Log files

The root `log.md` follows the OKF log format (OKF §9): date-grouped entries,
newest first, with `YYYY-MM-DD` headings. Every entry MUST start with a nonempty
bold lead word followed by a colon: `* **<lead word>**:`. The preferred vocabulary
includes `Initialization`, `Creation`, `Update`, `Move`, `Area created`, and
`Deprecation`, and entries SHOULD use one when it expresses the event. Unfamiliar
lead words remain conformant because OKF makes the vocabulary extensible (OKF §9).

The log records **knowledge lifecycle events only**: concept creation,
substantive change, deprecation, replacement, a move (§8.2), and the creation of an
area (§3.1), which is a structural commitment worth a dated record. It MUST NOT
record source events that produced no durable knowledge, formatting-only edits, or
unrelated repository activity.

A move is logged with both paths, because the log is where a reader whose link went
stale finds out where the concept went:

```markdown
* **Move**: [Critical I/B Owed](/initial-business/critical-i-b-owed.md) — from the
  bundle root, into the area its subject earned.
```

```markdown
# Knowledge Log

## 2026-07-31
* **Area created**: Grouped the request and analysis under their shared `reporting/` subject.
* **Area created**: Established `ways-of-working/` for durable project conventions.
* **Creation**: Recorded [PDF export feasibility](/reporting/pdf-export-feasibility.md).
* **Creation**: Defined the project relationship label [Assessed by](/ways-of-working/relationship-labels.md).
* **Update**: Verified [Include PDF annotations in the export](/reporting/include-pdf-annotations.md).

## 2026-07-30
* **Initialization**: Established the knowledge bundle under the Concepta OKF Profile 2026.1.
* **Creation**: Recorded [Include PDF annotations in the export](/reporting/include-pdf-annotations.md) from the reporting demo.
* **Creation**: Mirrored the [reporting demo transcript](/references/2026-07-30-reporting-demo-transcript.md).
```

The log is authored history, not a projection of current bundle state. It is the
source of truth for the curated account of how knowledge evolved; concepts and Git
history may corroborate it but cannot mechanically reconstruct significance or
completeness. Additional scoped logs at lower levels are permitted (OKF §9) and
optional.

---

## 11. The profile declaration

A bundle following this profile MUST contain `profile.md` at its root: an
ordinary concept of `type: Knowledge Profile`.

Its body MUST use the **first fenced `yaml` block** as the machine-readable
declaration, and that block MUST declare both release values shown here:

```yaml
concepta_profile: "2026.1"
okf_version: "0.2"
```

The declared `concepta_profile` MUST be `"2026.1"`. The declared `okf_version`
MUST be `"0.2"` and MUST agree with the root index (§9), because Profile 2026.1
binds exactly to OKF 0.2. Declaring the
profile in a concept body rather than a frontmatter field is deliberate: it
keeps the profile free of custom frontmatter (§5.1), so the bundle stays plain
OKF to every other consumer. `types.md` and `actors.md` follow the same reasoning
— tables in a body, not schema in frontmatter.

The declaration selects one immutable Profile release; it does not define,
inject, omit, replace, or parameterize that release's rules. `profile.md` MUST
NOT act as a standalone Profile definition, extension registry, second schema,
or place to restate or override OKF. Whether an implementation accepts caller
policy belongs exclusively to the companion guide.

---

## 12. Mirrored source material

External material MUST enter the bundle only through `references/` (§3.4), and
mirroring MUST be **pull-based**. An artifact MAY be mirrored only when a durable
concept cites it through OKF `sources`, its availability is genuinely at risk, and
the repository's visibility is appropriate for the material. Being outside project
control is evidence to consider, not by itself an availability risk.

An artifact MUST NOT be mirrored merely because a meeting, call, or thread
happened. Confirming that the content may live at repository visibility is part of
mirroring: the bundle inherits the repository's access controls (the profile defines
no per-concept scheme), so mirroring widens who can read the material.

Mirrored markdown artifacts are concepts. They MUST carry the Profile baseline and
an OKF `sources` entry naming the original; they MUST remain immutable snapshots
once cited.
A mirrored transcript is an ordinary source concept: it *preserves* an artifact
produced by the interaction, while an Interaction Record *interprets* the durable
combined context. The mirror does not substitute for that interpretation.

Non-markdown assets under `references/` are not concepts and carry no
frontmatter; the concepts citing them supply their context. A source directory
MAY separate the originals it preserves into its `raw/` tier (§3.4); the mirror
derived from an original then sits beside `raw/`, its `sources` entry naming
the original.

By medium:

| Medium | Policy |
|--------|--------|
| Text — transcripts, exported documents, chat threads | MAY be mirrored in full; MUST be sanitized where confidentiality demands |
| Images | MAY be mirrored when a concept cites them; MUST be optimized first |
| Video, audio, other heavy binaries | MUST NOT be committed; stay external and linked. When their content must survive the external system, authors SHOULD mirror an appropriate transcript instead |

Curated context about an external system that stays external MAY be an ordinary
concept whose `resource` names that system; no mirror is required.

**Recording a decision not to mirror.** Deciding *against* mirroring is as durable as
deciding for it, and it should be visible where a reader goes looking for the source.
When an artifact is deliberately not mirrored — confidentiality, repository
visibility, size, or a policy that keeps it external — its `sources[].resource`
MUST retain ordinary OKF §5.1 meaning: use its followable URL or path when one is
available, or a scope descriptor when the source is inherently unfollowable. Authors
SHOULD state the reason for non-mirroring in the body when it is material to future
preservation.

```yaml
sources:
  - id: demo-0730
    resource: Client demo recording, 30 July 2026 — retained outside this repository
    title: Reporting demo, 30 July 2026
    author: process:meeting-platform
    last_modified: 2026-07-30
```

A scope descriptor is preferable to pretending an unfollowable source has a path,
but it MUST NOT replace a known followable resource merely to avoid an availability
advisory. Mirroring policy never weakens or reinterprets OKF provenance.

Because heavy binaries never enter the bundle, the profile needs no Git LFS,
replication, or archival policy, and defines none.

---

## 13. Derived projections

Indexes (§9) are **projections**: derived mechanically from concepts, discardable,
and rebuildable at any time. An index MUST NOT become a source of truth. The
authored root log is history and is expressly outside this category (§10).

The Profile adds no graph contract. Markdown links and provenance retain their
OKF meanings; relationship labels and registry tables remain ordinary body
Markdown. Graph consumers follow OKF directly.

Reading a kind as a set — every ADR, the whole glossary, all open questions — is a
projection filtered by `type`, not a directory. That is what allows directories to
name subjects (§3) without losing kind-first navigation.

---

## 14. Conformance

### 14.1 Distinct conformance and assessment results

**OKF conformance** is inherited verbatim from OKF §11. A bundle is
OKF-conformant if every non-reserved `.md` file has parseable YAML frontmatter,
every frontmatter block carries a non-empty `type`, and every reserved file
follows the OKF index or log structure. These are the only conditions a
consumer may **reject** a bundle for.

**Profile conformance** is the additional bar set by this document: an
OKF-conformant Profiled Bundle satisfies every MUST and MUST NOT in its declared
release, regardless of whether a Deterministic Rule or Judgment Rule assesses
it. A bundle may pass OKF conformance while failing Profile conformance. The two
results are independent: a Profile result does not alter, reclassify, or replace
the OKF result.

**Automated Profile Validation** exposes the independent OKF result and the
Deterministic Rule result separately and leaves Judgment Rules explicitly
unassessed. Its orchestration and result-state contract belongs exclusively to
the companion guide.

**Profile Review** assesses Judgment Rules contextually and reports its result
separately from Automated Profile Validation. **Complete Profile Assessment**
combines both bodies of evidence; neither one alone claims complete Profile
conformance.

Normative force and assessment mode are independent. A mandatory Judgment Rule
remains mandatory, and an automated advisory remains non-blocking. Neither
assessment mode changes or reinterprets OKF conformance.

Deterministic structural failures include a missing required root file; a missing
conditional actor registry; a registry with the wrong structural table shape; a
missing or semantically stale index; a malformed or out-of-order root log; a root
index carrying no `okf_version`; and a missing, unparseable, or disagreeing profile
declaration. Deterministic concept failures include a missing or empty `type`,
`title`, `description`, or `status`; a non-OKF `status` value; a producer-defined
frontmatter field; a type registry missing or altering a standard row, using the
wrong standard or extension order, or omitting a used type; an invalid actor `Side`
or `Active` value; overlapping periods for one actor; and malformed source entries
or attribution joins. Literal tag duplication with machine-readable type, status, or
trust values is also deterministic.

Deterministic external-boundary failures include a malformed Relationships entry
that does not contain exactly one label and one target. Contextual meaning is not
inferred merely because this shape is mechanically visible.

Contextual Profile Review assesses whether a project directory names a
genuine shared subject, whether placement follows that subject, whether structure
is speculative, whether a purported subject concept contains durable knowledge
rather than duplicating navigation, and whether the authored log records material
lifecycle events. It also assesses the durable-capture and concept-boundary rules;
whether a standard or project-specific type and its registered meaning fit the
content; whether metadata, actor identity and history, sources, status, freshness,
and tags are truthful in context. For external boundaries it assesses relationship
meaning, project-label definitions, execution and specification lifecycle ownership,
the identity meaning of dates and preserved external IDs, repairability of known
external citations during moves, stable-concept deletion exceptions, and whether a
mirror is cited, genuinely at availability risk, safe at repository visibility, and
appropriately sanitized and, where required, optimized. It also assesses media
classification: the Profile defines no extension, MIME, signature, or byte threshold
from which a validator could consistently identify audio, video, or another heavy
binary.
Profile Review assesses the complete path rule because an externally cited ID has no
Profile-specific syntax that a validator could distinguish from the authored slug.
Neither assessment mode checks type-specific
body templates; §5.3 defines none. A small genuine area is not a finding.

Other advisories include missing `generated` provenance; a registered
project-specific type; a concept sitting beside an area of the same name rather
than inside it; a nonstandard relationship label; and an unresolved internal link.
These advisories MUST NOT affect Profile conformance, the automated gate, or exit
status. A relationship to an execution record may prompt contextual move review but
is not itself a finding (§8.2).

**A concept without a `verified` event is not a finding.** Absence of verification is
meaningful information, not a deviation (§6.2, OKF §5.3). Tooling MUST NOT report it,
because the only way an author can clear such a report is to record a verification
that did not happen — turning a diagnostic into a corruption of the trust model.

Tooling MAY *summarize* trust tiers and organizational provenance across a bundle,
since knowing how much of a bundle is unverified or internally asserted is useful. A
summary is not a finding and MUST NOT affect exit status.

### 14.2 Tolerant reading

Consumers MUST preserve OKF's tolerant-reader behaviour (OKF §11). Unknown
concept types, unknown frontmatter keys, unknown relationship labels, unregistered
actors, missing optional content, and broken links MUST remain loadable. Unknown
frontmatter SHOULD remain available to downstream consumers rather than being
dropped on round-trip, preserving OKF §4.1's exact force.

The type and actor registries are producer-side declarations. They make drift
visible inside a bundle; they MUST NOT be read as closed vocabularies that license
rejecting a concept, and a consumer encountering an unlisted type or actor behaves
exactly as OKF §11 requires.

External resource availability MUST NOT be a conformance gate: a link that
404s today is a link, not a malformed document.

Valid OKF that this profile does not describe is content to carry forward
untouched. It may come from a producer outside Concepta, or from a Concepta author
using an OKF mechanism this document simply never mentions (§1.3) — the two are
indistinguishable and both are correct. Tooling MUST NOT report a concept for using
an OKF 0.2 mechanism the profile is silent about: a validator that treats profile
silence as a closed world converts deference into a diagnostic, and pressures
authors away from the upstream spec this profile binds to.

## 15. Versioning and release evidence

### 15.1 Binding to OKF

Every profile release binds to **exactly one** OKF version. This release binds to
OKF 0.2 exactly.

Every normative Profile rule MUST pass the same rule-level compatibility test:
it uses only constructs OKF 0.2 permits, preserves every OKF field and reserved
file's upstream meaning, leaves the OKF graph contract uninterpreted, keeps the
independent OKF result unchanged, and leaves the bundle normally readable by a
generic OKF consumer. A rule that needs a new OKF field or meaning MUST be
rejected or pursued upstream before a later Profile release adopts it.

The release-specific, non-normative compatibility review records that test for
each rule at
[`docs/compatibility-review.md`](../docs/compatibility-review.md).
Compatibility evidence answers whether each rule preserves OKF. The separate
implementation coverage matrix at
[`implementation/profile-coverage.md`](../implementation/profile-coverage.md)
assigns each rule to Automated Profile Validation or Profile Review and answers
how Concepta assesses it. Neither artifact substitutes for the other, and the
release MUST NOT be published while either is incomplete.

An upstream OKF release requires a new profile release and a compatibility
review, even when no Concepta convention otherwise changes, so that a
compatibility claim is always explicit and testable. A profile release MUST NOT
claim compatibility with an OKF version it has not been reviewed against.

Because the binding is exact, references to the upstream specification SHOULD be
pinned to the commit or tag carrying that version rather than to a moving branch.

The profile and OKF are separately versioned documents, and §15.2 gives the profile a
version format OKF does not use so the two can never be mistaken for one another.
Prose MUST still name which document a version refers to; the machine-readable
declaration (§11) is unambiguous because it carries both keys.

### 15.2 Profile versions

A profile version is `<year>.<serial>` — `2026.1` is the first release of 2026, `2026.2`
the second. The serial does not reset against anything but the year, and versions order
naturally.

**The format is deliberately not `<major>.<minor>` or `<major>.<minor>.<patch>`,
because OKF uses the first of those.** A semver profile version would put two
unrelated numbers in one shape beside `okf_version` — "profile 0.2.0 binds OKF 0.2"
is a sentence that has to be read twice. A dated serial cannot collide with an OKF
version now or after any future OKF release, which is a property no semver
discipline can promise, since it would require predicting upstream's numbering.

What semver would carry is carried better in words. Each release states its own
migration impact in §15.3 — whether an existing conformant bundle stays conformant,
and what it must do if not — and that sentence is what a reader actually needs; a
lone digit could not carry it honestly.

**The structural model is not frozen.** The profile has been used on a small number of
bundles, and a release MAY still change how bundles are shaped, stating the migration
in §15.3. When that stops being true it will be said here, in this section, rather than
signalled by a digit.

OKF's normative requirements always take precedence over any profile release
(§1).

### 15.3 Change record

**2026.1.** Initial release. Binds OKF 0.2 exactly, published together with the
rule-level compatibility review and the implementation coverage matrix (§15.1).
Amended in place during its QA period (ADR-0006): §3.4 and §12 add the optional
per-source `raw/` tier for verbatim originals under `references/`. Driver: the
first migration QA showed originals and derived mirrors mixing in one tier with
nothing structural marking the boundary. Migration impact: none — the tier is a
MAY, and its markdown restriction binds only bundles that adopt it; a bundle
conformant before the amendment remains conformant unchanged.
A second QA-period amendment (ADR-0007): §9 writes targets as relative URLs and
compares them percent-decoded. Driver: the same migration's verbatim originals
carry filenames — spaces, parentheses, characters outside ASCII — that no target
spelling could satisfy, because Markdown parsing normalizes destinations to a
percent-encoded form the raw-path comparison then rejected. Migration impact:
none — every previously conformant target decodes to itself.

Future releases add one entry each here, newest first, naming the sections
touched, the **driver** — what real use revealed the gap — and the migration
impact for bundles conformant to the release before it.

---

## Appendix A: Worked example

One bundle showing the profile's central separations: a **source event** produces
**durable knowledge**, which links to an **execution record**, with **indexes and a
log** serving different roles: indexes are generated navigation, while the log is
authored history. Its two reporting concepts form a small genuine subject area;
there is no numeric minimum.

A client raises a request during a demo; the recording platform expires in 30 days,
so the transcript is mirrored; an analysis follows; the request is specified in
GitHub.

```text
knowledge/
  index.md
  log.md
  profile.md
  types.md
  actors.md
  reporting/
    index.md
    include-pdf-annotations.md        # Request
    pdf-export-feasibility.md         # Analysis
  ways-of-working/
    index.md
    relationship-labels.md            # Guide defining the project label Assessed by
  references/
    index.md
    2026-07-30-reporting-demo-transcript.md
    annotation-layout.json            # Referenced asset, not a concept
```

The two concepts live in `reporting/` because the existing corpus demonstrates
their shared subject. The count neither earns nor forbids that placement. There is
no `requests/` or `analyses/`, because those name kinds rather than subjects.

The demo itself is not a concept, and no Interaction Record was written: only one
outcome mattered, so the request links straight to its source (§4.3), and
`interactions/` does not exist.

`include-pdf-annotations.md` — the durable outcome, verified by a human,
citing the mirrored transcript, and linked to execution:

```markdown
---
type: Request
title: Include PDF annotations in the export
description: Client asks that reviewer annotations survive the PDF export.
status: draft
generated: { by: claude-code/opus-5, at: 2026-07-30T16:20:00Z }
verified: { by: human:chris, at: 2026-07-31T09:00:00Z }
tags: [reporting, export]
sources:
  - id: demo-0730
    resource: /references/2026-07-30-reporting-demo-transcript.md
    title: Reporting demo transcript, 30 July 2026
    author: process:meeting-transcription
    last_modified: 2026-07-30
---

# Request

Reviewer annotations must appear in the exported PDF, positioned as they are on
screen.[^demo-0730]

# Context

Raised while reviewing a draft export during the reporting demo.

# Relationships

- Specified by: [Annotation export spec](https://github.com/conceptadev/example/issues/128)
- Assessed by: [PDF export feasibility](/reporting/pdf-export-feasibility.md)

[^demo-0730]: Reporting demo transcript, 30 July 2026
```

`pdf-export-feasibility.md` — a separate concept because findings are
reusable independently of the request, with a real freshness horizon (§6.4):

```markdown
---
type: Analysis
title: PDF export feasibility for annotations
description: Whether the current renderer can place annotations without exceeding the generation budget.
status: draft
generated: { by: claude-code/opus-5, at: 2026-07-31T11:00:00Z }
stale_after: 2026-11-01
sources:
  - id: layout-sample
    resource: /references/annotation-layout.json
    title: Exported annotation layout sample
---

# Question

Can annotations be positioned in the exported PDF within the existing
generation budget? This analysis applies to the current renderer contract
through 31 October 2026; the contract changes on 1 November.

# Findings

The renderer exposes absolute placement; annotation geometry is already
persisted alongside review state.[^layout-sample]

# Recommendation

Proceed. Budget headroom is adequate at current document sizes.

# Relationships

- Refines: [Include PDF annotations in the export](/reporting/include-pdf-annotations.md)
- Constrained by: [Pagination contract](/reporting/pagination-contract.md)

[^layout-sample]: Exported annotation layout sample
```

`references/2026-07-30-reporting-demo-transcript.md` — mirrored because the
recording expires; an immutable source concept, not an interpreted outcome (§12):

```markdown
---
type: Meeting Transcript
title: Reporting demo transcript, 30 July 2026
description: Verbatim transcript of the reporting demo with the client review team.
status: stable
generated: { by: process:meeting-transcription, at: 2026-07-30T15:55:00Z }
sources:
  - resource: https://example-meetings.test/recordings/8412
    title: Reporting demo recording (retention: 30 days)
    author: process:meeting-platform
---

# Transcript

The original recording expires after 30 days. This transcript is retained because
the request cites it and its content is suitable for this repository's visibility.

[15:02] ...
```

`actors.md` — four actor IDs, including unknown affiliation and one historical
change, so the organizational question is answered only where evidence permits
(§6.1.1):

```markdown
---
type: Actor Registry
title: Actors
description: Actor IDs mapped to identity, affiliation, role, and active period.
status: stable
generated: { by: claude-code/opus-5, at: 2026-07-30T16:20:00Z }
---

| Actor ID | Name | Organization | Side | Role | Active |
|----------|------|--------------|------|------|--------|
| `human:chris` | Christiano Higuto | Concepta | internal | Engineering lead | 2026-01-01 – |
| `claude-code/opus-5` | Claude Code | Anthropic | tool | Authoring agent | 2026-06-01 – |
| `process:meeting-platform` | Meeting platform recording | unknown | unknown | Recording process | unknown |
| `process:meeting-transcription` | Meeting transcription | Concepta | internal | Transcription process | 2026-03-01 – 2026-08-01 |
| `process:meeting-transcription` | Meeting transcription | Example Transcription Vendor | vendor | Transcription process | 2026-08-01 – |
```

`log.md` — lifecycle events only. The demo appears nowhere; its outcomes do:

```markdown
# Knowledge Log

## 2026-07-31
* **Area created**: Grouped the request and analysis under their shared `reporting/` subject.
* **Area created**: Established `ways-of-working/` for durable project conventions.
* **Creation**: Recorded [PDF export feasibility](/reporting/pdf-export-feasibility.md).
* **Creation**: Defined the project relationship label [Assessed by](/ways-of-working/relationship-labels.md).
* **Update**: Verified [Include PDF annotations in the export](/reporting/include-pdf-annotations.md).

## 2026-07-30
* **Initialization**: Established the knowledge bundle under the Concepta OKF Profile 2026.1.
* **Creation**: Recorded [Include PDF annotations in the export](/reporting/include-pdf-annotations.md) from the reporting demo.
* **Creation**: Mirrored the [reporting demo transcript](/references/2026-07-30-reporting-demo-transcript.md).
```

Reading the bundle back out, an ordinary OKF graph consumer discovers the
Markdown links as untyped edges and the request's internal source as the
provenance edge OKF §5.1 defines. Relationship labels remain readable body context;
registry rows remain lookup data and create no Profile-only nodes or edges. The
not-yet-written pagination target remains an unresolved OKF edge and produces only
the non-blocking Profile advisory §7.1 requires.

The project-specific `Assessed by` label is defined once in
`ways-of-working/relationship-labels.md`. It remains ordinary body context and
produces the non-blocking extension advisory §7.2 requires.
