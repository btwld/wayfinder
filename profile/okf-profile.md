# Bitwild OKF Profile

**Version 2026.3** — profiles **OKF 0.2 exactly**

Status: Proposed

Bitwild Profile 2026.3 is the proposed release. Release 2026.2 is preserved
unchanged under `profile/versions/okf-profile-2026.2.md`.

The Bitwild OKF Profile is a set of conventions for keeping durable project
knowledge as an [Open Knowledge Format][okf] bundle in the same repository as the
code it describes. It is a *profile*, not a format: it defines no file type and
never changes what an OKF field means. Its one frontmatter key, `relationships`
(§7.2), is an additional producer key of the kind OKF §4.1 permits. Every other
mechanism it uses — bundles, concepts, frontmatter families, cross-links,
indexes, logs — is defined by OKF and used with its OKF meaning.

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
[spec]: https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/ad30107c31c06aec8a7d5636e0d1058118604e6f/SPEC.md

---

## 1. Motivation

Bitwild runs many codebases with many contributors, and durable project
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
   and agents, so a reader arriving at any Bitwild repository already knows how
   the bundle is put together, even where the subjects differ.
4. Keep execution systems authoritative: work items and delivery records — issues,
   tickets, pull requests — stay in GitHub and Linear and are linked, never
   mirrored. What makes something an execution record is that a tracker owns its
   state, not the genre of document it is (§7.3).
5. Remain interoperable — a Bitwild bundle MUST be readable by any OKF
   consumer with no knowledge of this profile.
6. Make conventions versioned, explicitly bound to bundles, and mechanically checkable.

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
how* Bitwild uses it, never *what it means*.

| OKF | Mechanism | In this profile |
|-----|-----------|-----------------|
| §2 | Bundle, concept, concept ID, frontmatter, body, link, source, provenance | Inherited verbatim (§2) |
| §3 | Directory tree of markdown, domain-independent structure | Constrained: fixed bundle-root files and project directories name subjects (§3) |
| §3.1 | Reserved `index.md` / `log.md` | Inherited; usage constrained (§9, §10) |
| §4.1 | Frontmatter, required `type`, recommended `title`/`description`/`resource`/`tags`, producer extensions | Constrained for Bitwild producers: `type`, `title`, `description`, and `status` are required, types are declared by the selected Profile binding, tags use its declared vocabulary, and the only producer key is the release-declared `relationships` (§5.1, §5.2, §7.2) |
| §4.1 | Types are not centrally registered; consumers tolerate unknown types | Inherited: the selected type registry is a producer-side declaration and never a reason to reject (§5.2, §14.2) |
| §4.2 | Free-form body, structural markdown, conventional headings, footnote attribution | Inherited: no type-specific template, and no body content carries Profile-specific machine meaning (§5.3) |
| §5 | Timestamp-valued keys as ISO 8601 datetimes with an explicit UTC offset | Inherited; a date-only or offset-less value MUST NOT be written (§6.5) |
| §5.1 | `sources`, credibility signals, `usage_window`, per-claim footnotes | Inherited unchanged; mechanisms surfaced rather than summarized (§6.1) |
| §5.2 | `generated`, `verified` | Constrained: `generated` is recommended and must never be fabricated; `verified` records only verification that occurred, and its absence is meaningful (§6.2) |
| §5.3 | Trust tiers derived, not stored | Inherited unchanged; the binding actor lookup makes organizational identity legible without touching tiers (§6.1.1) |
| §5.4 | `status`: `draft` / `stable` / `deprecated` | Constrained to the knowledge lifecycle of the document only; assessing the subject is body content, with no field and no derivation (§6.3, §6.3.1) |
| §5.5 | `stale_after` as an absolute instant | Constrained: evidence-based, conditional (§6.4) |
| §6.1 | Markdown links, bundle-relative preferred, broken links tolerated | Inherited; typed relationship targets follow the same rules (§7); internal links repaired on a move (§8.2) |
| §6.2 | Path-valued fields | Inherited unchanged |
| §6.3 | `references/` mirrors external material as concepts | Inherited; mirroring policy added (§12) |
| §7 | Actor convention (`producer/version`, `human:`, `process:`) | Inherited verbatim; IDs stay opaque and optional affiliation lives in binding lookup (§6.1.1) |
| §8 | Index files, `okf_version` at bundle root only | Constrained: every index is the reference generator's output, required wherever it writes one (§9) |
| §9 | Date-grouped log entries, newest first | Constrained: knowledge lifecycle events only (§10) |
| §10 | Attested Computation and its computation keys | Inherited unchanged (§1.3) |
| §11 | Tolerant-reader conformance | Inherited and reinforced (§14.2) |
| §12 | `okf_version` declaration and version semantics | Inherited; profile binds one OKF version (§15) |

**The table is not a boundary.** It enumerates the mechanisms Bitwild constrains;
it does not limit what a bundle may use. Anything OKF 0.2 defines that this
document never mentions — a frontmatter key, a body convention, a structural
affordance, or a whole family such as Attested Computation — is available
unchanged and carries its OKF meaning. A producer facing a question this profile
does not answer MUST read the pinned specification and follow it, and MUST NOT mint
a Bitwild convention in its place. That failure mode is the one this profile is
least able to detect, because a locally invented rule looks like a convention
rather than a divergence, and it is how a profile quietly becomes the competing
standard §1.2 forbids.

Silence is also not prohibition. Where OKF permits something and this document says
nothing, it is permitted. The narrowings are the ones stated as such —
frontmatter fields neither OKF nor the release declares (§5.1), directory names
(§3), `status` semantics (§6.3), index presence and content (§9) — and each is
written as an explicit MUST or MUST NOT. Absence of a rule is never one of them.

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
and versions existing practice for Bitwild projects.

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
  and declared by the selected Profile binding (§5.2). Kind is never carried by a
  directory name.
- **Type registry**: the selected Profile manifest's standard types plus the project binding's custom types (§5.2).
- **Relationship vocabulary**: the selected Profile manifest's standard relationship names plus the project binding's additional names (§7.2).
- **Actor lookup**: the project binding's metadata for actor IDs used in the bundle (§6.1.1).
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
- **Profiled Bundle**: an OKF bundle that is selected by a project binding to a Bitwild Profile release and is assessed against both OKF and that release.
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
not subdivide distribution. Bitwild adoption binds one such bundle to
`knowledge/` in the companion guide; that repository choice is not a bundle rule.

```text
<bundle>/
  index.md              # Root index (§9). Carries okf_version.
  log.md                # Root log (§10).
  <concept>.md          # A concept whose subject has no area yet (§3.1).

  <area>/               # Area (§3.1). Mixed types, project-named.
    index.md            # The area's generated index (§9).
    <concept>.md        # Every other file is an ordinary concept. None is privileged.
    <sub-area>/         # Nested areas are permitted (§3.1).
      index.md
      <concept>.md

  architecture/         # Default areas (§3.2). Created lazily.
  ways-of-working/
  interactions/         # Time-axis directory (§3.3).
  references/           # Mirrored source material (§3.4, §12).
  computations/         # Shared Attested Computations (§3.6; OKF §10.4).
```

Every project directory in the tree MUST name the **subject** its contents share,
not a kind of document. Kind is
carried by `type` (§5.2), so a directory named after a document kind — `decisions/`,
`analyses/`, `guides/`, `adr/` — duplicates metadata the concept already carries and
scatters one subject across many folders. The three exceptions are `interactions/` and
`references/`, whose organizing axis is time rather than subject (§3.3, §3.4), and
`computations/`, the co-location directory OKF §10.4 itself names for Attested
Computations (§3.6).

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
4. **Indexed.** An area MUST contain its generated `index.md` (§9).
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
covers `interactions/`, `references/`, and `computations/` (§3.3, §3.4, §3.6): a
bundle MAY omit any or all of these five Profile-defined directories.

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

**These two, plus `interactions/`, `references/`, and `computations/`, are the only
directory names this profile specifies.** Every other directory name in this document, including in the
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
organized into subdirectories. Its directories carry the generated indexes §9
requires, like any other directory; one holding only non-concept assets needs
none.

A source directory MAY keep the verbatim originals it preserves in a `raw/`
subdirectory. Within `raw/` and any of its subdirectories, no markdown file is
permitted: everything in the tier is a non-concept asset (§12) and stays
byte-for-byte, and its directories, holding only assets, carry no `index.md`
(§9). A readable mirror derived
from an original is a sibling of `raw/` in its source directory, never inside
it. Because this rule keys on the name, `raw` is reserved within `references/`
and MUST NOT name a source directory. The tier belongs to a source directory
alone: `raw/` MUST NOT sit directly under `references/`, which is not a source
directory — a flat `references/` organizes into source directories before
adopting the tier.

What may be mirrored, and when, is specified in §12.

### 3.5 Root files

A bundle MUST contain `index.md` and `log.md` at its root. They retain their OKF
meanings: navigation and authored knowledge history. Profile selection, type
extensions, tags, and actor lookup live in the project binding (§11), not in
bundle concepts. A bundle using this release MUST NOT carry legacy root
`profile.md`, `types.md`, or `actors.md` registries as competing configuration.
Ordinary concepts MAY sit at the root; every other `.md` file is a concept.

The five Profile-defined directory names and the subject-placement rules in
§3.1–§3.4 and §3.6 remain unchanged. `wayfinder.json` selects a Profile for a **whole
bundle**, never for an area or individual directory. It does not contain a
placement map, and it does not turn type or tag names into folders.

### 3.6 The `computations/` directory

OKF §10.4 makes co-locating Attested Computations "a directory choice (a
`computations/` folder with an `index.md`), not a frontmatter one", and its
worked example keeps computations there. This profile adopts that choice as a
named directory rather than calling it a kind-named folder, because OKF is
authoritative where the two would differ.

A bundle MAY keep its Attested Computation concepts in `computations/` at the
bundle root. A bundle MAY instead file a computation with the subject it computes
under §3.3. When `computations/` exists:

1. It MUST contain only `Attested Computation` concepts and its `index.md`. It
   is not an area: it sorts no mixed knowledge by kind, because its membership is
   one type by construction, as `interactions/` is.
2. It MAY nest under §3.1 rule 5, for example by the subject or runtime the
   computations share, and each of its directories MUST contain its generated
   `index.md` (§9).
3. The concepts that use a computation stay with their own subjects and link to
   it with an ordinary link (OKF §10.4). A computation's location changes no
   consumer's placement.

The ban's two reasons fail here as they fail for `interactions/`: the folder
duplicates nothing, because OKF itself names it as the computations' home, and it
scatters no subject, because one computation ordinarily serves consumers in
several subjects (OKF §10.1, "one computation, many consumers").

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

Every frontmatter key a concept uses is defined by OKF, with its OKF meaning, or
declared by the selected Profile release. OKF §4.1 lets producers include
additional keys; this release declares exactly one, `relationships` (§7.2).

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
each concept's index entry (§9), and explicit `status` prevents OKF's absent-means-stable
default from misrepresenting a draft. Authors MUST choose truthful values; Profile
Review assesses semantic accuracy while Automated Profile Validation checks the
fields' presence, shape, and permitted `status` value (§14.1).

`generated` SHOULD record how the current content was produced. Its absence is an
advisory, never a failure, and an author or tool MUST NOT fabricate generation
provenance to satisfy the recommendation (§6.2).

The optional OKF fields `resource`, `tags`, `sources`, `verified`, and
`stale_after` remain available with their OKF-defined meanings. Sections §5.1 and
§6 state the Profile's specific producer rules for using them.
Bitwild producers MAY use the frontmatter keys the selected Profile release
declares, and MUST NOT introduce any other namespaced or producer-defined
frontmatter field. A declared key MUST NOT be a key OKF 0.2 defines and MUST NOT
give an OKF key another meaning; a Profile that needs an OKF field to mean
something else pursues it upstream (§15.1). A project binding cannot declare frontmatter keys; it
adds vocabulary only (§11). This constrains what Bitwild writes; it does not
change OKF's tolerant-reader contract. Consumers MUST NOT reject a document for
an unknown field and SHOULD preserve unknown keys when round-tripping, exactly as
OKF requires (OKF §4.1, §11; §14.2).
Declaring keys in the release, rather than letting each producer add its own,
keeps the profile interoperable by construction: a generic OKF reader loads a
declared key as one more unknown key, and every Profile consumer reads it with
its one declared meaning.

**`tags` carry topic, and nothing else.** A tag groups concepts by what they are
about — a domain, capability, or theme a reader might sweep for. A declared tag
name MUST NOT equal a declared type name, an OKF `status` value (`draft`,
`stable`, `deprecated`), an OKF trust tier (`unverified`, `machine-confirmed`,
`human-reviewed`), or a declared relationship name (§7.2). Because every used
tag is declared, no tag on a concept can then repeat its type, status, trust
tier, or a relationship name. A tag also MUST NOT serve as a semantic alias for
kind, lifecycle, trust, or how settled the subject is. Automated Profile
Validation checks the declared names when it reads the binding (§11); Profile
Review assesses semantic aliases (§14.1). Each of those meanings has a field or mechanism that a consumer reads, and a tag is either
redundant on the day it is written or wrong on the day the real signal changes —
`partially-resolved` on a question is a fact about an inbound `partially-resolves`
relationship, and nothing updates it when a second one lands. The prohibition is the same
one §5.2, §6.3, and §6.3.1 each make for their own field, stated once for the field
that has no meaning of its own to defend it.

Every used tag MUST appear exactly once in the selected Profile manifest or
project binding's declared tag vocabulary (§11), and a concept MUST NOT repeat
a tag value. Definitions MUST have unique names and nonempty descriptions;
project tags MUST NOT collide with Profile tags. A declaration does not apply a
tag automatically. Whether a declared tag truthfully describes a concept remains
Profile Review. OKF readers still tolerate unknown tags (§14.2).

### 5.2 Types and the type registry

`type` carries the kind of document a concept is, and it is the **only** place
kind is carried: not the directory (§3), not the filename, not a tag. The
installed `bitwild_profile/2026.3` manifest (§11) MUST declare the twelve
standard types below in this order and with these meanings. The project binding
MAY add project-specific types with a nonempty name and truthful description.
Custom names MUST be unique and MUST NOT collide with a standard name. Every
used concept type MUST resolve in the merged registry; an unregistered use is
a producer-side Profile failure, not grounds for a generic OKF reader to reject
the document (§14.2). A registered custom type is conformant and is reported
as a summary entry (§14.1) so recurring extensions can inform a later release.

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
| `Attested Computation` | An OKF-defined sanctioned computation with a checkable execution receipt (OKF §10) |

A standard type MUST match its intended meaning. A custom type MUST match the
meaning declared in the binding. Both are Judgment Rules assessed by Profile
Review; automated validation checks names and membership. The old structural
`Knowledge Profile`, `Type Registry`, and `Actor Registry` types are not standards
in this release because their root concepts are retired (§3.5). Consumers MUST
tolerate types they do not recognize (OKF §11).

Three boundaries are worth stating, because each was routinely blurred before it
was written down:

- **A `Business Rule` is not a `Decision`.** A rule describes how the business
  already works and nobody chose it; a decision records a choice with alternatives.
  A rule that turns out to be a policy someone selected is a Decision, and the rule
  concept SHOULD carry a `depends-on` relationship to it.
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
  a `specified-by` relationship, and §7.3 forbids mirroring it. A spec the project maintains as
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
open is read from inbound relationships (§7.2): a `resolves` relationship means
closed, a `partially-resolves` relationship means narrowed, neither means open. A resolved question
stays `stable` rather than becoming `deprecated` — how understanding arrived at an
answer is knowledge in its own right.

### 5.3 Body conventions

Bodies remain free-form, as OKF permits. The Profile defines no type-specific body
template and missing headings are not a conformance finding. Compact authoring
templates belong to the Profile skill, where they can help writers without becoming
bundle rules. No part of the body carries Profile-specific machine meaning: typed
relationships live in frontmatter (§7.2), and a `# Relationships` heading is
ordinary prose.

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
    last_modified: 2026-07-30T00:00:00Z
relationships:
  - relationship: specified-by
    resource: https://github.com/conceptadev/example/issues/128
---

# Request

Reviewer annotations must appear in the exported PDF, positioned as they are
on screen.[^demo-0730]

# Context

Raised during the reporting demo while reviewing a draft export. Reviewers
currently re-enter annotations by hand after export.

# Constraints

Export must stay within the existing generation budget.

[^demo-0730]: Reporting demo transcript, 30 July 2026
```

---

## 6. Provenance, trust, and lifecycle

The OKF frontmatter families (OKF §5) are used with their upstream semantics.
This section states only *when* Bitwild applies them.

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

### 6.1.1 Actor lookup

OKF actor IDs in `generated.by`, `verified[].by`, and `sources[].author` stay
opaque and retain their OKF meanings. The project binding (§11) MAY provide an
`actors` map of lookup metadata. When an actor ID is used in a bundle, the
selected binding MUST contain that exact ID with a nonempty `name`. Optional
`organization`, `role`, and `side` add context; `side`, when present, MUST be
`client`, `internal`, `vendor`, `tool`, or `unknown`. Authors MUST use `unknown`
rather than inventing an affiliation. The metadata MUST be truthful, but lookup
does not prove authorship, verification, or a trust tier.

The lookup is not an OKF graph edge and MUST NOT change OKF trust derivation.
A generic consumer still reads any unlisted actor normally. The project binding
MAY be shared by several bundles when their actor IDs have the same meanings;
a project needing different metadata uses a separate binding. Unlike the
superseded `actors.md` table, this release does not prescribe affiliation
periods or infer them from an ID. Time-dependent affiliation, when material,
belongs in ordinary project knowledge and contextual review, not a fabricated
static lookup.

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

**Nor is it derivable from links.** `constrained-by` relationships toward open
items are useful navigation — a reader following one finds what is missing — but they encode no
assessment: the name means the target limits this concept, which a fully settled
constraint also does, and a target MAY be knowledge not yet written (§7.1, §7.2). Absence of
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

Per OKF §5.5 it is an absolute instant, not a calendar day: a concept is stale
when `now >= stale_after`. A value written without an explicit UTC offset does
not name an instant, so it MUST NOT be used (§6.5).

Type alone neither supplies nor rules out that evidence. The same type may describe
a time-bounded present condition or an enduring historical fact; the content and
its sources decide whether `stale_after` is truthful.

### 6.5 Writing timestamps

Every timestamp-valued key in OKF — `generated.at`, `verified[].at`,
`stale_after`, `sources[].last_modified`, `usage_window.from` and
`usage_window.to` — is an ISO 8601 datetime with an explicit UTC offset. A
concept MUST NOT write a date-only or offset-less value where OKF expects a
timestamp, because such a value names no instant.

---

## 7. Cross-linking and relationships

### 7.1 Links

Links between concepts follow OKF §6.1. Bundle-relative links (a leading `/`)
SHOULD be preferred for internal targets, because they survive document moves
within a subdirectory. An internal link whose target is absent MAY remain in a
conformant bundle and MAY represent knowledge not yet written. It is reported
as a summary entry, not a finding (§14.1); Profile Review decides whether it is
a useful planned edge or a repairable mistake in context.

Provenance and navigation stay separate mechanisms: `sources` records where
content came from, links record how a reader traverses the knowledge, and
`relationships` records the links whose meaning is worth typing (§7.2).

### 7.2 Relationships

A concept MAY carry a top-level `relationships` frontmatter key recording typed
links from it to other resources. When present, `relationships` MUST be a list,
and each entry MUST be a mapping with exactly two keys: `relationship`, a name in
the selected relationship vocabulary, and `resource`, a nonempty target:

```yaml
relationships:
  - relationship: superseded-by
    resource: /architecture/token-contract.md
  - relationship: depends-on
    resource: /architecture/support-offline-mode.md
  - relationship: implemented-by
    resource: https://github.com/conceptadev/example/pull/142
```

`resource` MUST be a link target as OKF §6.1 defines one, a bundle path or a URL,
and an internal target SHOULD be bundle-relative, as §7.1 prefers for links.
Unlike `sources[].resource`, it is never a scope descriptor: a relationship
points at something a reader can follow. An internal target absent from the
bundle MAY remain and MAY represent knowledge not yet written; like an unresolved
link (§7.1), it is reported as a summary entry, not a finding (§14.1).

Relationships are not provenance and MUST NOT be recorded in `sources`. OKF §5.1
defines `sources` as what a concept's content derives from and lets a consumer
infer credibility through it; a concept that depends on, refines, or is tracked by
its target has not derived its content from it. `relationships` is the additional
producer key §5.1 declares, so it neither reuses nor redefines an OKF key. A
generic OKF consumer loads it as an unknown key, and every link in the body stays
an ordinary OKF edge.

The installed `bitwild_profile/2026.3` manifest (§11) MUST declare the standard
relationship names below in this order and with these meanings:

| Name | Meaning, read from the containing concept outward |
|------|---------------------------------------------------|
| `superseded-by` | This concept has been replaced by the target |
| `depends-on` | This concept is only valid while the target holds |
| `constrained-by` | The target limits what this concept may do |
| `part-of` | This concept is a constituent of the target, which is incomplete without it |
| `refines` | This concept narrows or sharpens the target |
| `specified-by` | The target is the specification of this concept |
| `implemented-by` | The target is the work that delivers this concept |
| `resolves` | This concept fully answers or closes the target |
| `partially-resolves` | This concept answers part of the target, which remains open |
| `tracked-by` | The target is the work-tracking record that chases this concept |
| `related-to` | An unlabelled association worth surfacing |

`part-of` is written in one direction only. Backlinks are computed, never authored
(§13), so a reciprocal "composed of" name would be redundant. Use it where a
concept is a constituent rather than a narrowing: two buckets that sum to a balance
are `part-of` it, not `refines` of it and not peers of it.

`tracked-by` names the edge every project was reaching for `related-to` to express: an
open item lives in the bundle as knowledge, while who owes it and by when lives in the
tracker (§6.3, §7.3), and the two need a link. It is neither `specified-by` nor
`implemented-by` — a question is not specified or implemented by the issue chasing it —
and it carries no state: whether the item is still open is read from inbound `resolves`
and `partially-resolves` relationships (§5.2), never from the tracker record's status.

`resolves` and `partially-resolves` are distinguished because most evidence narrows
an open item without closing it. Reserve `resolves` for genuine closure; a source
that moves a question forward while leaving it open uses `partially-resolves`. Using
`resolves` loosely makes open items read as settled. Together they are how a
`Question`'s openness is read (§5.2), which is why the distinction is load-bearing
rather than stylistic.

Reaching for `related-to` repeatedly signals a missing name. A project finding it on
a large share of its relationships is better served naming the relationship — with a
project-declared name, or by proposing one for a later profile release.

Every used relationship name MUST appear in the selected Profile manifest or
project binding's declared relationship vocabulary (§11). The project binding MAY
declare additional names; definitions MUST have unique names and nonempty, truthful
descriptions, and project names MUST NOT collide with Profile names. The
declaration is where a project defines a name's meaning once, so authors apply it
consistently. Profile Review assesses whether the name and target express the
intended relationship. Consumers MUST tolerate names they do not recognize (§14.2).

Markdown links in the body remain valid untyped edges. A `# Relationships`
heading in the body has no Profile meaning in this release: it is ordinary prose,
and the links under it are ordinary links.

### 7.3 Execution records

Execution systems stay authoritative and external. GitHub issues and pull
requests, and Linear records, are linked from concepts — with `specified-by`,
`implemented-by`, or `tracked-by` relationships (§7.2) — and MUST NOT be mirrored
into the bundle. Their state is read from the tracker, never copied into frontmatter or body.

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

1. Every known inbound link and relationship target inside the bundle points at
   the new path.
2. Every affected index entry is regenerated (§9).
3. `log.md` records the move (§10).

A move that leaves a known inbound internal link unchanged is incomplete. The
unresolved edge remains loadable and is reported as a summary entry under §7.1; it
does not become an OKF or Profile conformance failure merely because it reveals
unfinished move work.

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

A concept carrying a `specified-by`, `tracked-by`, or `implemented-by`
relationship toward an execution record (§7.3) SHOULD be reviewed for external
citations before a move; the relationship alone does not prove that its path is
frozen.

This is also why §3.1 grows areas rather than predicting them — but not because a
move is expensive, since by the rule above it is cheap. An area name is a claim
about the subject its contents share, and the current corpus must support that
claim. Counting concepts cannot establish it.

### 8.3 Deprecation and deletion

The normal retirement path for a stable concept SHOULD be deprecation, not
deletion: set `status: deprecated`. Where a successor exists, the deprecated
concept MUST carry a `superseded-by` relationship to it. Historical meaning stays
inspectable.

Draft concepts MAY be deleted outright. A stable concept MAY be hard-deleted only
for an exceptional security, privacy, legal, secret-removal, or genuinely erroneous-
content reason that outweighs historical preservation. Profile Review MUST assess
that exception and the treatment of known citations and successors; deletion cannot
be inferred safely from final bundle state alone.

---

## 9. Index files

Index files follow the OKF index format (OKF §8). Indexes are what make a bundle
navigable without reading it, so an agent reaches the root index, then a
directory index, then a concept.

Indexes are generated. For each `index.md` that the OKF reference index
generator writes for the bundle, the bundle MUST contain that file with exactly
the generator's text, generated with the root index declaring
`okf_version: "0.2"` (§11). The reference generator is `OkfIndexGenerator` in
`okf` package release 0.5.0. Because the generator's text is the contract, an
`okf` release whose generator writes different text changes which bytes
conform, and adopting it requires a Profile revision recorded in §15.3; an
`okf` release that leaves that text unchanged requires none (§15.1). The
companion implementation guide binds how tools pin that release and detect
drift from it. This profile adds no grouping, ordering, label, target, or
description rule of its own. An index MUST NOT carry authored content: a hand edit is drift that the
next regeneration discards, and knowledge worth keeping belongs in a concept.

The generator writes an index for every area, sub-area, and `computations/`
directory, and for each level of `references/` at or above a mirrored concept. A
directory holding only non-concept assets, such as a `raw/` tier (§3.4), gets no
generated index and MUST NOT carry one: the generator would still link to a
leftover index it no longer maintains. A bundle with no concepts gets no generated root
index; until its first concept exists, its root `index.md` MUST declare
`okf_version: "0.2"` and list only `log.md`.

Requiring the generator's output tightens OKF §8, where an entry SHOULD carry
the linked concept's description and generation is optional. Every index is
then mechanically checkable and safely regenerable, with no second source of
truth. Using the reference generator instead of a Profile-specific projection
keeps one index shape across OKF tooling.

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
* **Creation**: Recorded how reviewers apply the project relationship `assessed-by` in [Assessment guidance](/ways-of-working/assessment-guidance.md).
* **Update**: Verified [Include PDF annotations in the export](/reporting/include-pdf-annotations.md).

## 2026-07-30
* **Initialization**: Established the knowledge bundle under the Bitwild OKF Profile 2026.3.
* **Creation**: Recorded [Include PDF annotations in the export](/reporting/include-pdf-annotations.md) from the reporting demo.
* **Creation**: Mirrored the [reporting demo transcript](/references/2026-07-30-reporting-demo-transcript.md).
```

The log is authored history, not a projection of current bundle state. It is the
source of truth for the curated account of how knowledge evolved; concepts and Git
history may corroborate it but cannot mechanically reconstruct significance or
completeness. Additional scoped logs at lower levels are permitted (OKF §9) and
optional.

---

## 11. Profile selection and binding

A bundle following this release MUST be named by exactly one `applies_to` path
in a `profiles` entry of project-root `wayfinder.json` version 1. The entry key
is the Profile identity. Its `source` MUST identify a Git repository, a ref,
and the path of a declarative Profile manifest inside that revision. The
manifest's identity MUST match the entry key and its release MUST be 2026.3.
The effective chain MUST reach `bitwild_profile/2026.3`, whose manifest binds
exactly to OKF 0.2 and whose rules and standard vocabulary are installed with
the validator. The bundle root index MUST declare `okf_version: "0.2"`.
Unknown Profile IDs or releases MUST NOT silently fall back.

A Profile entry MAY name one parent through `extends`, independently of its
`applies_to` list. A parent used only for inheritance MAY have an empty
`applies_to` list. Inheritance is additive: an entry MAY add type, tag, and
relationship definitions and actor lookup, but names MUST be unique across the
effective chain and MUST NOT collide with installed standards. An entry MUST
NOT declare frontmatter keys (§5.1) or reinterpret OKF semantics. A non-base
entry MUST extend a chain reaching `bitwild_profile`; the base MUST NOT extend
another entry. Missing parents, cycles, and ambiguous composition MUST NOT be
accepted.

A Profile's automated rules are its rule catalog, data the installed validator
evaluates. A non-base entry's manifest MAY name a rule catalog in its source
(`rules`, a path relative to the manifest in the same revision). The catalog
MUST declare the manifest's identity and release, MUST report in the namespace
that identity names (the entry key with each `_` written as `-`), and MUST NOT
declare frontmatter keys. Its rules add findings in that namespace only: a
child MUST NOT replace, omit, re-grade, or parameterize an ancestor's rules, so
the findings of every ancestor are the same with or without the child. The
base `bitwild_profile` source MUST NOT name a catalog; the installed one is
authoritative. A catalog that names a subject, slot, builtin, or keyword the
installed validator does not support MUST make dispatch `UNSUPPORTED`; a
catalog is never partially applied.

`applies_to` paths MUST be relative, unique, inside the project after symlink
resolution, and not nested within one another. Several independent bundles MAY
share an entry. A nested directory within a bundle inherits its bundle's
Profile and MUST NOT select another one (§3).

`wayfinder.json` and any resolution lock are project configuration, not OKF
concepts or a second frontmatter schema. They MUST NOT be placed inside the
bundle or projected into its `index.md`. Version 1 has no `bundles` array,
`implements` string, or `default_bundle`. The root `profile.md` selector from
2026.2 does not dispatch this release.

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
    last_modified: 2026-07-30T00:00:00Z
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

Graph views are projections as well. The Profile adds nothing to OKF's graph:
Markdown links and provenance retain their OKF meanings, and graph consumers
follow OKF directly. Tooling MAY project the typed relationships of §7.2 beside
OKF's graph as additional named edges, provided every OKF edge and its meaning
stay unchanged.

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

The installed rule catalog (§11) is the machine-readable form of the rules
Automated Profile Validation applies for this release. Each catalog rule cites
the clause it assesses and describes what that clause requires or permits, and
it MUST agree with that clause. The catalog adds no requirement of its own: where a
rule and the clause it cites differ, this document governs and the catalog is
in error.

**Profile Review** assesses Judgment Rules contextually and reports its result
separately from Automated Profile Validation. **Complete Profile Assessment**
combines both bodies of evidence; neither one alone claims complete Profile
conformance.

Normative force and assessment mode are independent. A mandatory Judgment Rule
remains mandatory, and an automated advisory remains non-blocking. Neither
assessment mode changes or reinterprets OKF conformance.

Deterministic structural failures include a missing required root file, an
invalid project binding, duplicate registry entries, a missing or stale
generated index, a malformed or out-of-order root log, a root index carrying no
`okf_version`, and an unavailable Profile release or OKF-version disagreement.
Deterministic concept failures include a missing or empty `type`, `title`,
`description`, or `status`; a non-OKF `status` value; a frontmatter field neither
OKF nor the release declares; an unregistered used type or actor; invalid actor
lookup metadata; duplicate or undeclared tags; malformed source entries or
attribution joins; and a malformed `relationships` value or entry, including an
undeclared relationship name. A declared tag name that equals a declared type
name, an OKF status value or trust tier, or a declared relationship name is an
invalid project binding (§5.1). Contextual meaning is not inferred merely because a relationship's
shape is mechanically visible.

Contextual Profile Review assesses whether a project directory names a
genuine shared subject, whether placement follows that subject, whether structure
is speculative, whether a purported subject concept contains durable knowledge
rather than duplicating navigation, and whether the authored log records material
lifecycle events. It also assesses the durable-capture and concept-boundary rules;
whether a standard or project-specific type and its registered meaning fit the
content; whether metadata, actor identity, sources, status, freshness,
and tags are truthful in context. For external boundaries it assesses relationship
meaning, project relationship-name definitions, execution and specification lifecycle ownership,
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

Other advisories include missing `generated` provenance; a concept sitting
beside an area of the same name rather than inside it; and an internal link or
relationship target that is not bundle-relative. Each asks an author to act or
to review. These advisories MUST NOT affect Profile conformance, the automated
gate, or exit status. A relationship to an execution record may prompt contextual move review but
is not itself a finding (§8.2).

**A concept without a `verified` event is not a finding.** Absence of verification is
meaningful information, not a deviation (§6.2, OKF §5.3). Tooling MUST NOT report it,
because the only way an author can clear such a report is to record a verification
that did not happen — turning a diagnostic into a corruption of the trust model.

Tooling MAY *summarize* trust tiers and organizational provenance across a bundle,
since knowing how much of a bundle is unverified or internally asserted is useful. A
summary is not a finding and MUST NOT affect exit status.

Automated Profile Validation reports what this Profile permits as **summary
entries**, not advisories: a registered project-specific type (§5.2), and an
unresolved internal link or relationship target, which stays a loadable edge
(§7.1, §7.2, §14.2). Tooling MUST report summary entries separately from
findings, and they MUST NOT affect Profile conformance, the automated gate, or
exit status.

### 14.2 Tolerant reading

Consumers MUST preserve OKF's tolerant-reader behaviour (OKF §11). Unknown
concept types, unknown frontmatter keys, unknown relationship names, unregistered
actors, missing optional content, and broken links MUST remain loadable. Unknown
frontmatter SHOULD remain available to downstream consumers rather than being
dropped on round-trip, preserving OKF §4.1's exact force.

The type, tag, relationship, and actor vocabularies are producer-side
declarations in the binding. They make drift visible to Profile tooling; they
MUST NOT license a generic OKF consumer to reject a concept. A consumer
encountering an unlisted type, tag, relationship name, or actor behaves exactly
as OKF §11 requires.

External resource availability MUST NOT be a conformance gate: a link that
404s today is a link, not a malformed document.

Valid OKF that this profile does not describe is content to carry forward
untouched. It may come from a producer outside Bitwild, or from a Bitwild author
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
how Bitwild assesses it. Neither artifact substitutes for the other, and the
release MUST NOT be published while either is incomplete.

An upstream OKF release requires a new profile release and a compatibility
review, even when no Bitwild convention otherwise changes, so that a
compatibility claim is always explicit and testable. A profile release MUST NOT
claim compatibility with an OKF version it has not been reviewed against.

Because the binding is exact, references to the upstream specification SHOULD be
pinned to the commit or tag carrying that version rather than to a moving branch.

The binding names a specification version, not a toolchain, with one
exception: §9 makes the text written by the reference index generator in `okf`
package release 0.5.0 part of this release's contract. An `okf` release that
changes no specification text and leaves that generator's output unchanged
needs no Profile release. One whose generator output differs needs a Profile
revision before Profile tooling adopts it, even though OKF 0.2 is unchanged.

The profile and OKF are separately versioned documents, and §15.2 gives the profile a
version format OKF does not use so the two can never be mistaken for one another.
Prose MUST still name which document a version refers to. The machine-readable
binding names the Profile release, while the root index declares OKF 0.2 (§11).

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

**2026.3.** Moves Profile selection and project vocabulary out of bundle
concepts into direct Git-sourced project-root `wayfinder.json` entries. Entries
may add vocabulary through explicit parent chains. The installed
`bitwild_profile` validator remains closed. Affected sections:
§§1.3, 2, 3.5, 5.1–5.2, 6.1.1, 9, 11, 14, 15.3 and Appendix A. Driver: real
adoption and validation work found repeated standard `types.md` tables,
mandatory actor tables for routine agent provenance, and `profile.md`
configuration masquerading as knowledge; multiple independent bundles need
reusable but distinct bindings, and a repeatable source revision across
machines. The OKF-defined Attested Computation type joins the standard
registry so producers can use §10 without declaring an OKF type as custom. The
subject-placement rule is unchanged; `computations/` joins the named directories
as the OKF §10.4 home for Attested Computations (§3, §3.2, §3.5, §3.6), so the
profile follows OKF's own directory choice instead of reading it as a kind-named folder. Migration
impact: an existing conformant 2026.2 bundle remains conformant to **2026.2**
and continues to validate under that release. To adopt 2026.3, create a
direct-source entry, resolve and commit its lock, move custom types, tags, and
actor IDs into the entry, remove the
three legacy root registry/declaration concepts, regenerate the root index, and
retain `index.md` and `log.md`. Used tags must be declared. Material actor
affiliation history from the old table must be preserved as ordinary knowledge
before the table is removed; a single JSON lookup cannot express dated rows.
This is an opt-in
migration, not a silent reinterpretation of old bundles.

Revised in place before publication: every index is the output of the OKF
reference index generator (§9) instead of a Profile-defined projection. The
`Bundle`, `Directories`, and `Assets` groups, the Profile type order, and the
label, target-encoding, and per-nonempty-directory rules are withdrawn, and a
directory holding only non-concept assets, such as a `raw/` tier, needs no
index. §9 names the generator's `okf` release, 0.5.0, and §15.1 states that a
release changing the generator's output needs a Profile revision. Affected
sections: §§1.3, 3, 3.1, 3.4, 3.6, 5.1, 9, 14.1, 15.1, and Appendix A.
Driver: the custom projection diverged from the index shape OKF's own tooling
generates, so bundles needed a Profile-specific generator to stay conformant;
a second knowledge base on the same okf release already checks its indexes with
`okf index --check`,
and teammates on the native `wayfinder` binary need the generator without a
Dart toolchain. Migration impact: an index written to the earlier 2026.3
projection no longer conforms. `wayfinder validate --fix` regenerates every
index the generator writes but never deletes a file, so delete each `index.md`
it then reports as one the generator does not write, such as one left in a
`raw/` tier or another asset-only directory. 2026.2 bundles and the 2026.2
projection are unaffected.

Revised in place before publication: typed relationships move from the
`# Relationships` body section to the top-level frontmatter key `relationships`,
a list of `relationship` and `resource` mappings, which this release declares as
its one additional producer key under OKF §4.1. A declared key never reuses or
redefines an OKF key, and relationships stay out of `sources`, whose OKF §5.1
meaning is derivation. Relationship names become declared vocabulary like tags:
the manifest declares the eleven standard names in kebab-case, a project binding
MAY declare more, and an undeclared name is an error rather than an advisory.
Affected sections: the preamble, §§1.3, 2, 5.1–5.4, 6.3.1, 7.1–7.3, 8.2, 8.3,
10, 11, 13, 14.1, 14.2, and Appendix A. Driver: a labelled body link reached OKF's graph,
and Wayfinder graph and search, only as an untyped link, and checking the body
grammar needed a Profile-specific Markdown parser; a second knowledge base on
the same okf release records its typed edges in frontmatter, where its gate checks
names and targets with a schema. Migration impact: a bundle written to the earlier 2026.3 text
that carries a `# Relationships` section still conforms, but the section is
ordinary prose and its labels no longer type anything. To keep them, move each
bullet into `relationships`, with its label in kebab-case as `relationship` and
its link target as `resource`, delete the emptied section, and declare each
nonstandard label in the binding's `relationships` list. 2026.2 bundles keep the
body section under 2026.2.

Revised in place before publication: a non-base entry's source may ship a rule
catalog, the data form every Profile's automated rules now take, and its rules
add findings in the entry's own namespace. The earlier text forbade loading
executable rules from a source; a catalog is data the installed validator
evaluates, so that line holds and the prohibition narrows to replacing,
omitting, re-grading, or parameterizing an ancestor's rules, declaring
frontmatter keys, and shipping a catalog for the base. §14.1 makes the
installed catalog the machine-readable form of the automated rules, which must
agree with the clauses they cite. Affected sections: §§11 and 14.1.
Driver: a second knowledge base on the same okf release keeps its own rules
beside its vocabulary, and a child Profile with vocabulary but no rules could
not express a stricter policy, such as a closed type subset, without a
validator release. Migration impact: none for bundles; a conformant 2026.3
bundle stays conformant, since no existing source names a catalog and an
ancestor's findings are unchanged by a child's. A child catalog the installed
validator cannot evaluate makes dispatch `UNSUPPORTED` rather than silently
dropping rules; upgrade the validator or correct the catalog. 2026.2 bundles
are unaffected.

Revised in place before publication: what the Profile permits is reported as a
summary entry, not an advisory. A registered project-specific type and an
unresolved internal link or relationship target are conformant, so tooling
reports them apart from findings, and only advisories that ask an author to act
or review remain. A declared tag name MUST NOT equal a declared type name, an
OKF status value or trust tier, or a declared relationship name; this replaces
the per-concept check of a tag against that concept's own type, status, trust
tier, and relationship names. Affected sections: §§5.1, 5.2, 7.1, 7.2, 8.2,
and 14.1. Driver: SARIF output for code scanning raised every advisory as a
warning, including each project type in use and each planned link, which no
author action clears; and once every used tag is declared, a tag that repeats
another vocabulary is a property of the declaration, which the per-concept
check reported once per concept that used it and not at all while unused.
Migration impact: no concept changes, and no bundle's result changes except
through its tags. A binding that declares a tag equal to any declared type
name, status value, trust tier, or relationship name now fails at
configuration, before any concept is assessed, even when no concept uses the
tag or the tag equals a type other than the type of the concept that carries
it; rename or remove that tag. 2026.2 bundles are unaffected.

**2026.2.** Adopts the upstream OKF 0.2 revision that makes every timestamp an
ISO 8601 datetime with an explicit UTC offset, and moves the pinned
specification to its canonical repository, `open-knowledge-format` at
`ad30107` — the same text as `knowledge-catalog` `62432a0`, which the `okf`
package names. Affected sections: the §5.5 row of the OKF section map, §6.4,
the new §6.5, §11's release binding, and every timestamp in the examples.
Driver: upstream restated `stale_after` as an absolute instant compared against
`now` rather than a calendar day, dropped `last_modified`'s date-only type, and
made `usage_window` a datetime range; a profile that still called `stale_after`
a date would contradict the specification it binds.
Migration impact: a bundle conformant under 2026.1 stays conformant. The `okf`
package reports a date-only timestamp as the non-blocking
`okf/timestamp-without-offset` advisory and leaves its conformance verdict
unchanged, so no bundle becomes non-conformant by standing still. Two
exceptions are worth stating plainly: `okf validate --strict` escalates
advisories to failures and so begins failing on date-only timestamps it used to
accept, and a concept east of UTC may now go stale later than it did when
staleness was a local calendar comparison. `okf format --migrate-timestamps`
rewrites date-only values to `T00:00:00Z`.

Amended in place: §6.5 withdraws the three producer SHOULDs (quoted timestamps,
block-style structured values, `verified` as a list) and drops the day-only
`T00:00:00Z` authoring sentence. Driver: those sentences contradicted or
extended the OKF specification's own examples. YAML spelling and day-resolution
belong to OKF and `okf format --migrate-timestamps`. Migration impact: none — a
bundle conformant under the unamended 2026.2 stays conformant.

**2026.1.** Initial release. Binds OKF 0.2 exactly, published together with the
rule-level compatibility review and the implementation coverage matrix (§15.1).
Amended in place during its QA period (ADR-0006): §3.4 and §12 add the optional
per-source `raw/` tier for verbatim originals under `references/`. Driver: the
first migration QA showed originals and derived mirrors mixing in one tier with
nothing structural marking the boundary. Migration impact: none — the tier is a
MAY, and its markdown restriction binds only bundles that adopt it; a bundle
conformant before the amendment remains conformant unchanged.
A second QA-period amendment (ADR-0007): §9 writes targets as relative URLs and
compares them percent-decoded, rejecting the spellings a URL reads differently —
raw `?`/`#`, escapes decoding to `/`. Driver: the same migration's verbatim
originals carry filenames — spaces, parentheses, characters outside ASCII — that
no target spelling could satisfy, because Markdown parsing normalizes
destinations to a percent-encoded form the raw-path comparison then rejected.
Migration impact: a previously conformant target decodes to itself and stays
conformant unless it carried a raw `?` or `#`, which now needs the encoded
spelling a URL consumer actually resolves to the file.

Future releases add one entry each here, newest first, naming the sections
touched, the **driver** — what real use revealed the gap — and the migration
impact for bundles conformant to the release before it.

---

## Appendix A: Worked example

The 2026.2 worked bundle remains available in the immutable snapshot and
`examples/knowledge/` as a migration reference. A minimal 2026.3 project has:

```text
project/
  wayfinder.json
  knowledge/
    index.md
    log.md
    reporting/
      index.md
      request.md
      analysis.md
```

`reporting/` is an illustrative project subject, not a prescribed directory.
The root index is the generator's output: it lists the `reporting/` directory
but not `log.md` or `wayfinder.json`. `Request` and `Analysis` come from the
installed standard vocabulary; only project tags, relationship names, actors,
or custom types appear in the entry. A separate `research/` bundle may appear in the same entry's
`applies_to` list or another entry with different vocabulary. It does not
inherit a Profile from `knowledge/`, and `knowledge/reporting/` cannot select
one.
