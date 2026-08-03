# Concepta OKF Profile

**Version 0.1.0** — profiles **OKF 0.2**

Status: Proposed

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
the pinned [OKF 0.2 specification][spec]. §1.3 lists what the profile inherits
unchanged, and §14 defines conformance.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are to be interpreted
as described in RFC 2119.

Adoption planning, validator construction, migration, and tooling rollout are
out of scope here. They belong to a companion implementation specification,
`concepta-okf-profile-spec.md`, which is **not yet written**; until it exists this
document is the only normative Concepta text.

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
  carries no reliable meaning.
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
3. Establish one vocabulary and one layout across repositories, teams, and
   agents, so a reader arriving at any Concepta repository already knows where
   to look.
4. Keep execution systems authoritative: specifications, issues, and delivery
   records stay in GitHub and Linear and are linked, never mirrored.
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

### 1.3 Inherited from OKF unchanged

The profile selects and constrains OKF; it never redefines it. Every mechanism
below keeps its OKF meaning. "Constrained" means the profile narrows *when or
how* Concepta uses it, never *what it means*.

| OKF | Mechanism | In this profile |
|-----|-----------|-----------------|
| §2 | Bundle, concept, concept ID, frontmatter, body, link, source, provenance | Inherited verbatim (§2) |
| §3 | Directory tree of markdown, domain-independent structure | Constrained: one bundle per repository, fixed root (§3) |
| §3.1 | Reserved `index.md` / `log.md` | Inherited; usage constrained (§9, §10) |
| §4.1 | Frontmatter, required `type`, recommended `title`/`description`/`resource`/`tags`, producer extensions | Constrained: a baseline is required, no custom fields added (§5.1) |
| §4.2 | Free-form body, structural markdown, conventional headings, footnote attribution | Constrained: recommended body shapes (§5.2) |
| §5.1 | `sources`, credibility signals, `usage_window`, per-claim footnotes | Inherited unchanged; mechanisms surfaced rather than summarized (§6.1) |
| §5.2 | `generated`, `verified` | Constrained: `generated` in the baseline; verification expected where a concept asserts confirmed fact, and its absence is a signal (§6.2) |
| §5.3 | Trust tiers derived, not stored | Inherited unchanged; optional actor registry makes organizational identity legible (§6.1) |
| §5.4 | `status`: `draft` / `stable` / `deprecated` | Constrained to the knowledge lifecycle of the document only; assessing the subject is body content, with no field and no derivation (§6.3, §6.3.1) |
| §5.5 | `stale_after` as an absolute date | Constrained: evidence-based, conditional (§6.4) |
| §6.1 | Markdown links, bundle-relative preferred, broken links tolerated | Inherited; labelled subset added (§7) |
| §6.2 | Path-valued fields | Inherited unchanged |
| §6.3 | `references/` mirrors external material as concepts | Inherited; mirroring policy added (§12) |
| §7 | Actor convention (`producer/version`, `human:`, `process:`) | Inherited verbatim |
| §8 | Index files, `okf_version` at bundle root only | Constrained: required per nonempty directory, deterministic (§9) |
| §9 | Date-grouped log entries, newest first | Constrained: knowledge lifecycle events only (§10) |
| §10 | Attested Computation and its computation keys | Inherited, unused by profile 0.1.0 (§14.3) |
| §11 | Tolerant-reader conformance | Inherited and reinforced (§14.2) |
| §12 | `okf_version` declaration and version semantics | Inherited; profile binds one OKF version (§15) |

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
- **Collection**: a directory immediately inside the bundle root holding
  concepts of exactly one type (§3.1). A collection is not a nested bundle.
- **Durable knowledge**: an outcome worth preserving in the project after the
  activity that produced it has ended. The subject matter of the bundle.
- **Source event**: an activity that may produce knowledge — a call, daily,
  planning session, demo, message, thread, or transcript. A source event is
  never itself a concept (§4).
- **Execution record**: an artifact in a work-tracking system — a
  specification, issue, ticket, or pull request. Execution records live outside
  the bundle and are linked, never mirrored (§7.3).
- **Projection**: an artifact derived mechanically from concepts, discardable
  and rebuildable. Indexes, logs, diagnostics, and graph views are projections
  (§13).
- **Mirror**: a copy of external source material committed under `references/`
  so provenance survives the external system (§12).
- **Promotion**: moving an outcome recorded inside one concept into a concept of
  its own, because it acquired an independent identity (§4.2).

---

## 3. Bundle structure

A repository owns exactly one bundle, rooted at `knowledge/`. A bundle MUST NOT
contain a nested bundle: directories inside the root organize concepts, they do
not subdivide distribution.

```text
knowledge/
  index.md              # Root index (§9). Carries okf_version.
  log.md                # Root log (§10).
  profile.md            # Profile declaration (§11).
  glossary/             # Collections (§3.1). Created lazily.
  rules/
  requests/
  interactions/
  analyses/
  decisions/
  adr/
  specifications/
  architecture/
  guides/
  references/           # Mirrored source material (§3.2, §12). Not a collection.
```

### 3.1 Collections

A collection is a directory immediately inside the bundle root. Collections
obey four rules:

1. **One type.** Every concept in a collection MUST declare the same `type`.
   A collection name therefore carries a reliable meaning.
2. **Lazy.** A collection that holds no concepts SHOULD NOT exist. An absent
   collection is not an incomplete bundle.
3. **Flat.** In profile 0.1.0 concepts sit directly inside their collection.
   Collections MUST NOT contain subdirectories.
4. **Indexed.** A nonempty collection MUST contain an `index.md` (§9).

The default collection-to-type mapping:

| Collection | Concept type | Intended content |
|------------|--------------|------------------|
| `glossary` | Glossary Definition | One project or domain term per concept |
| `rules` | Business Rule | One standing business rule, constraint, invariant, or policy per concept |
| `requests` | Request | Durable requests from any relevant source |
| `interactions` | Interaction Record | Interactions whose broader context is itself durable |
| `analyses` | Analysis | Investigation, feasibility, comparison, or recommendation |
| `decisions` | Decision | Durable non-architectural decisions with an independent lifecycle |
| `adr` | Architecture Decision Record | Architectural decisions in ADR form |
| `specifications` | Specification | Specifications intentionally stored inside the bundle |
| `architecture` | Architecture Document | Durable descriptions of the system architecture |
| `guides` | Guide | Durable operational or engineering guidance |

Short collection names pair with descriptive type names deliberately: paths stay
convenient to type and read, while `type` stays unambiguous in metadata.

Projects MAY introduce additional concept types and matching collections.
Consumers MUST tolerate types they do not recognize (OKF §11). A locally useful
type MAY be promoted into a later profile release.

Architecture Decision Record and Architecture Document are distinct types: the
first records a decision in the established ADR form, the second describes the
system without necessarily deciding anything.

**Choosing between `adr` and `decisions`.** Use `adr` when the decision shapes the
software's structure and an engineer deciding how to build would want to read it.
Use `decisions` for every other durable decision — process, commercial, scope,
sequencing, or governance. When a decision plausibly fits both, prefer `decisions`
and keep `adr` reserved for the system being built, so an ADR set stays readable as
the architecture record it is.

**A Business Rule is not a Decision.** A rule describes how the business already
works and nobody chose it; a decision records a choice with alternatives. A rule that
turns out to be a policy someone selected is a Decision, and the rule concept should
link to it with `Depends on`.

`rules` is deliberately formalism-neutral. A project MAY structure rule concepts using
SBVR — vocabulary, fact types, and definitional/derivation/behavioral rule classes —
or any other notation that suits its domain. The collection commits to *one standing
rule per concept*, not to a particular way of writing one.

### 3.2 The `references/` directory

`references/` carries the OKF §6.3 convention — external material mirrored into
the bundle as first-class concepts — and is **not** a collection. It is
therefore exempt from the one-type and flatness rules of §3.1: mirrored material
is heterogeneous, and it MAY be organized into subdirectories. A nonempty
`references/` MUST still carry an `index.md`, and so MUST each of its nonempty
subdirectories.

What may be mirrored, and when, is specified in §12.

### 3.3 Reserved filenames

`index.md` and `log.md` are reserved at every level, per OKF §3.1, and MUST NOT
be used for concept documents. Every other `.md` file in the tree is a concept.

---

## 4. Durable capture

The profile governs stored knowledge, not event ingestion. This section is what
keeps a bundle from degenerating into a meeting archive.

### 4.1 What earns a concept

A source event is only a source. A daily, planning session, demo, call, message,
or transcript MUST NOT become a concept merely because it occurred.

A concept is created when a source event produces durable knowledge worth
preserving: a meaningful request, a decision, an investigation and its findings,
an architectural constraint, a term, or reusable guidance. A source event that
produces none leaves nothing behind, and that is a correct outcome, not a gap.

Requests are ordinarily first-class concepts. A request outlives the interaction
that expressed it and can later be analyzed, specified, implemented, rejected,
superseded, or revisited — a lifecycle of its own, which is exactly what earns a
concept.

### 4.2 The promotion rule

Decisions, answers, questions, and other outcomes are placed by **identity**,
not by importance:

- **Keep the outcome inside an existing concept** when it has no meaningful
  identity or lifecycle outside that concept.
- **Promote it to its own concept** when it needs independent status,
  provenance, relationships, reuse, replacement, or history.

A small outcome that will never be referenced, verified, or superseded on its
own SHOULD stay where it arose. Promotion is reversible in practice only before
a concept stabilizes (§8.2), so a genuinely ambiguous outcome SHOULD start
embedded.

### 4.2.1 The inverse: when to split a concept

Promotion moves an outcome *out of* a concept. The opposite pressure arises as a
concept grows, and it has a different trigger.

A concept SHOULD be split when parts of it would carry materially different
**provenance**, **verification**, or **lifecycle**. Frontmatter applies to the whole
concept: one `sources` list, one `verified` history, one `status`. A concept holding
both confirmed and unconfirmed material cannot express that difference in frontmatter,
and averaging it is lossy in the one direction that matters — the unconfirmed parts
inherit the confidence of the confirmed ones.

Per-claim **provenance** does have a mechanism: footnotes keyed to a `sources[].id`
(§6.1). Per-claim **verification** does not. So mixed provenance inside one concept is
workable, and mixed verification is the signal to split.

Size alone is not a reason to split, and neither is heading count.

### 4.3 Interaction Records

An Interaction Record is optional. It is appropriate when an interaction's
*combined* context is itself durable — several linked outcomes, a negotiation,
a demo whose overall shape matters.

When only one outcome matters, that outcome SHOULD link directly to its original
external source, and no Interaction Record is required. An Interaction Record
MUST NOT be produced as routine minutes.

---

## 5. Concept documents

Every concept is an OKF concept document (OKF §4): UTF-8 markdown, YAML
frontmatter, free-form body.

### 5.1 Baseline frontmatter

Profile 0.1.0 introduces **no** frontmatter fields. Every key used is defined by
OKF, with its OKF meaning.

A concept SHOULD carry this baseline:

```yaml
---
type: <Concept type>
title: <Human-readable display name>
description: <One sentence summarizing the concept>
status: draft | stable | deprecated
generated: { by: <actor>, at: <ISO 8601 datetime> }
---
```

Only `type` is required for OKF conformance (OKF §4.1); the remaining four make
a concept's identity and lifecycle legible without opening the body, and
`description` is what indexes project (§9).

The optional OKF fields `resource`, `tags`, `sources`, `verified`, and
`stale_after` SHOULD be added whenever their OKF-defined meaning applies (§6).
Producers MUST NOT introduce Concepta-namespaced or otherwise custom fields in
profile 0.1.0. Establishing conventions before extending the schema keeps the
first release interoperable by construction.

### 5.2 Body conventions

Bodies remain free-form, as OKF permits. The profile recommends these shapes:

| Type | Recommended headings |
|------|----------------------|
| Request | Request, Context, Constraints, Relationships |
| Decision, Architecture Decision Record | Context, Decision, Consequences, Alternatives considered, Relationships |
| Analysis | Question, Findings, Recommendation, Relationships |
| Glossary Definition | Definition, Avoid, Relationships |
| Business Rule | Rule, Rationale, Consequences, Relationships |

These are advisory. A missing recommended heading is not a conformance failure
(§14.1). Of the body, only the `# Relationships` section (§7.2) carries
profile-specific machine meaning.

### 5.3 Example

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
    author: human:chris
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

`sources` owns provenance. A concept derived from a source event SHOULD record
that source, whether it is external (a call recording, a thread, a document) or
internal (a mirrored artifact under `references/`, another concept).

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

**Distinguishing sources by organization.** Where a project distinguishes sources
by organization — client versus internal, first-party versus derived — that distinction
lives in the actor IDs, and interpreting it requires knowing what each actor is. A
project MAY maintain an actor registry as an ordinary concept, mapping every actor ID
used in the bundle to its organization and role. Trust tiers (OKF §5.3) distinguish
human from machine, not client from internal; the registry is what makes the second
distinction legible.

### 6.2 Trust: `generated` and `verified`

`generated` belongs to the baseline (§5.1) and records how the current content
was produced.

A concept whose content **asserts confirmed fact** SHOULD have at least one
`verified` event, so its trust history is visible. The verifier MAY be a
person, an agent, or a process, expressed in the OKF actor convention. Recording
verification does not imply human review; the actor prefix says which kind it
was, and consumers derive trust tiers from that (OKF §5.3). The profile does not
require a human in the loop and does not forbid one.

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
tracker (§7.3).

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
vocabulary for it and SHOULD define that vocabulary once, in a `guides/` concept,
rather than leaving each author to invent one.

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

`stale_after` is evidence-based and conditional: it is declared only when the
content has a real freshness horizon.

Historical records — requests, decisions, ADRs, interactions, mirrored source
snapshots — describe something that happened and normally have no expiry; they
SHOULD omit `stale_after`. Time-sensitive analyses and architecture descriptions
MAY declare one. A concept MUST NOT be given an arbitrary expiry to satisfy a
convention.

---

## 7. Cross-linking and relationships

### 7.1 Links

Links between concepts follow OKF §6.1. Bundle-relative links (a leading `/`)
SHOULD be preferred for internal targets, because they survive document moves
within a subdirectory. Broken links are tolerated (OKF §6.1) and MAY represent
knowledge not yet written.

Provenance and navigation stay separate mechanisms: `sources` records where
content came from, links record how a reader traverses the knowledge.

### 7.2 The Relationships section

A concept MAY carry a `# Relationships` section giving selected links a stable
semantic label. Each bullet MUST carry exactly one label and one target:

```markdown
# Relationships

- Superseded by: [Token contract](/glossary/token-contract.md)
- Depends on: [Offline mode decision](/decisions/support-offline-mode.md)
- Implemented by: [PR #142](https://github.com/conceptadev/example/pull/142)
```

The core labels are:

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
| Related to | An unlabelled association worth surfacing |

`Part of` is written in one direction only. Backlinks are computed, never authored
(§13), so a reciprocal "composed of" label would be redundant. Use it where a
concept is a constituent rather than a narrowing: two buckets that sum to a balance
are `Part of` it, not `Refines` of it and not peers of it.

`Resolves` and `Partially resolves` are distinguished because most evidence narrows
an open item without closing it. Reserve `Resolves` for genuine closure; a source
that moves a question forward while leaving it open uses `Partially resolves`. Using
`Resolves` loosely makes open items read as settled.

Reaching for `Related to` repeatedly signals a missing label. A project finding it on
a large share of its edges is better served naming the relationship — with a
project-specific label, or by proposing one for a later profile release.

Projects MAY use additional labels, and consumers MUST tolerate labels they do
not recognize. Markdown links elsewhere in the body remain valid untyped edges;
labelling is a way to add meaning, never a requirement to link.

Profile 0.1.0 defines no frontmatter relationship schema.

### 7.3 Execution records

Execution systems stay authoritative and external. GitHub specifications,
issues, and pull requests, and Linear records, are linked from concepts —
ordinarily with `Specified by` or `Implemented by` — and MUST NOT be mirrored
into the bundle. Their state is read from the tracker, never copied into
frontmatter or body.

One concept MAY accumulate several execution records over time, and a concept
MAY never produce any. Neither is an inconsistency.

---

## 8. Identity and lifecycle

### 8.1 Concept IDs

A concept's ID is its path relative to the bundle root with `.md` removed (OKF
§2). IDs are therefore paths, and path choices are identity choices.

Paths use readable lowercase kebab-case. Dates appear only where chronology is
part of identity — Interaction Records and mirrored source snapshots. ADRs
retain their conventional sequence numbers. Status, owner, and priority MUST NOT
appear in a filename; they are metadata and would make identity churn.

Example IDs:

- `glossary/token-contract`
- `requests/include-pdf-annotations`
- `interactions/2026-07-30-reporting-demo`
- `analyses/pdf-export-feasibility`
- `decisions/support-offline-mode`
- `adr/0008-direct-token-consumption`
- `references/2026-07-30-reporting-demo-transcript`

### 8.2 Immutability

Once a concept reaches `stable`, its path MUST NOT change. Links, history, and
future graph identities all key off the path, and a rename breaks them silently.

Draft concepts MAY be moved freely.

### 8.3 Deprecation and deletion

The normal retirement path for a stable concept is deprecation, not deletion:
set `status: deprecated` and, where a successor exists, link it with
`Superseded by`. Historical meaning stays inspectable.

Draft concepts MAY be deleted outright. Hard deletion of a stable concept is
reserved for security, privacy, legal, or secret-removal obligations, which
override the preference for historical preservation.

---

## 9. Index files

Index files follow the OKF index format (OKF §8) exactly: no frontmatter, except
that the bundle-root `index.md` MAY carry `okf_version`.

A nonempty directory MUST contain an `index.md`: every collection, `references/`, and
any nonempty subdirectory of `references/` (§3.2). Indexes are what make a bundle
navigable without reading it, so an agent reaches the root index, then a collection
index, then a concept.

The root index declares the OKF version and enumerates the bundle: the profile
declaration, every nonempty collection, and `references/` when present.

```markdown
---
okf_version: "0.2"
---

# Knowledge

* [Concepta OKF Profile](profile.md) - Profile and OKF versions this bundle follows.
* [Glossary](glossary/) - One project or domain term per concept.
* [Requests](requests/) - Durable requests from any relevant source.
* [References](references/) - Mirrored source material cited by concepts.
```

A collection index enumerates the concepts immediately inside it, in the same
form.

**Grouping.** OKF §8 permits an index body to use *one or more* sections, each
grouping entries under a heading, and the stated purpose of an index is progressive
disclosure. A flat list stops serving that purpose as a collection grows: above
roughly **20 entries**, a collection index SHOULD group its concepts under headings
matching how a reader would look for them — by subdomain, by lifecycle, by area.

```markdown
# Initial Business

* [Critical I/B Owed](critical-i-b-owed.md) - The deadline-bearing portion of the balance.
* [Non-Critical I/B Owed](non-critical-i-b-owed.md) - The portion carrying no deadline.

# Billing

* [Consolidated Invoice](consolidated-invoice.md) - Parent-level document grouping site invoices.
```

Grouping headings are navigation, not content. They MUST NOT carry knowledge found
nowhere else, and MUST be reproducible from concept frontmatter — ordinarily `tags`,
or `status` when grouping by lifecycle. OKF §3.1 anticipates exactly this scan.

Indexes are **deterministic projections** (§13): each entry's description MUST
be copied exactly from the linked concept's `description`, and an index MUST NOT
contain knowledge found nowhere else. An index that becomes a source of truth
has stopped being regenerable.

The verbatim-description rule deliberately tightens OKF §8's SHOULD to a MUST,
because that is what makes an index mechanically checkable and safely regenerable. It
carries a cost: a concept and its index entry must be written as one operation.

---

## 10. Log files

The root `log.md` follows the OKF log format (OKF §9): date-grouped entries,
newest first, `YYYY-MM-DD` headings, with the conventional `**Creation**`,
`**Update**`, and `**Deprecation**` lead words.

The log records **knowledge lifecycle events only**: concept creation,
substantive change, deprecation, and replacement. It MUST NOT record source
events that produced no durable knowledge, formatting-only edits, or unrelated
repository activity.

```markdown
# Knowledge Log

## 2026-07-31
* **Update**: Verified [Include PDF annotations in the export](/requests/include-pdf-annotations.md).

## 2026-07-30
* **Creation**: Recorded [Include PDF annotations in the export](/requests/include-pdf-annotations.md) from the reporting demo.
* **Creation**: Mirrored the [reporting demo transcript](/references/2026-07-30-reporting-demo-transcript.md).
```

The concepts and Git history remain authoritative; the log is a discovery aid
that answers "how did understanding here evolve" without a `git log` archaeology
session. Additional scoped logs at lower levels are permitted (OKF §9) and
optional.

---

## 11. The profile declaration

A bundle following this profile MUST contain `profile.md` at its root: an
ordinary concept of `type: Knowledge Profile`.

Its body records the profile identity and the OKF version it binds to. The
**first fenced `yaml` block in the body** is the machine-readable declaration,
and tools MUST read exactly that block:

```yaml
concepta_profile: "0.1.0"
okf_version: "0.2"
```

The declared `okf_version` MUST agree with the root index (§9). Declaring the
profile in a concept body rather than a frontmatter field is deliberate: it
keeps profile 0.1.0 free of custom frontmatter (§5.1), so the bundle stays plain
OKF to every other consumer.

`profile.md` is not an extension registry, a second schema, or a place to
restate or override OKF.

---

## 12. Mirrored source material

External material enters the bundle only through `references/` (§3.2), and only
**pull-based**: an artifact is mirrored when a concept's `sources` needs to cite
it *and* its external home is ephemeral or outside project control — a chat
thread, a recording platform with a retention limit, a system the project does
not administer.

Nothing is mirrored because a meeting, call, or thread happened. Confirming that
the content may live at repository visibility is part of mirroring: the bundle
inherits the repository's access controls (profile 0.1.0 defines no per-concept
scheme), so mirroring widens who can read the material.

Mirrored markdown artifacts are concepts. They carry minimal frontmatter — for
example `type: Meeting Transcript` with `title`, `description`, `generated`, and
a `sources` entry naming the original — and are immutable snapshots once cited.
A mirrored transcript is not knowledge: an Interaction Record *interprets* an
interaction, a transcript merely *preserves* one.

Non-markdown assets under `references/` are not concepts and carry no
frontmatter; the concepts citing them supply their context.

By medium:

| Medium | Policy |
|--------|--------|
| Text — transcripts, exported documents, chat threads | MAY be mirrored in full; sanitized where confidentiality demands |
| Images | MAY be mirrored when a concept cites them; MUST be optimized first |
| Video, audio, other heavy binaries | MUST NOT be committed; stay external and linked. When their content must survive the external system, mirror the transcript instead |

Curated context about an external system that stays external is an ordinary
concept whose `resource` names that system — no mirror required.

**Recording a decision not to mirror.** Deciding *against* mirroring is as durable as
deciding for it, and it should be visible where a reader goes looking for the source.
When an artifact is deliberately not mirrored — confidentiality, repository
visibility, size, or a policy that keeps it external — cite it as an OKF §5.1 **scope
descriptor** in `sources[].resource`, a value the consumer cannot dereference, and
state the reason in the body.

```yaml
sources:
  - id: demo-0730
    resource: Client demo recording, 30 July 2026 — retained outside this repository
    title: Reporting demo, 30 July 2026
    author: human:chris
    last_modified: 2026-07-30
```

A scope descriptor is preferable to a path that does not resolve: it is honest about
being unfollowable, and it avoids minting a link that a later mirroring decision would
have to repair.

Because heavy binaries never enter the bundle, profile 0.1.0 needs no Git LFS,
replication, or archival policy, and defines none.

---

## 13. Derived projections

Indexes (§9), logs (§10), validator diagnostics, and any future graph view are
**projections**: derived mechanically from concepts, discardable, and rebuildable
at any time. A projection MUST NOT become a source of truth.

A knowledge graph, when built, derives entirely from the markdown bundle:

- Concepts become nodes, keyed by their path-based IDs (§8.1).
- Frontmatter contributes node metadata.
- `sources` entries pointing inside the bundle become provenance edges.
- Labelled Relationships bullets become typed edges (§7.2).
- Other markdown links become untyped edges.
- Backlinks are computed, never authored.
- External URLs and execution records become external nodes.

The graph MUST be completely rebuildable from the bundle. Nothing may exist only
in the graph.

---

## 14. Conformance

### 14.1 Two levels

**OKF conformance** is inherited verbatim from OKF §11. A bundle is
OKF-conformant if every non-reserved `.md` file has parseable YAML frontmatter,
every frontmatter block carries a non-empty `type`, and every reserved file
follows the OKF index or log structure. These are the only conditions a
consumer may **reject** a bundle for.

**Profile conformance** is the additional bar set by this document: the MUST
requirements of §3 through §13. A bundle may be OKF-conformant while failing
profile conformance.

Tooling MUST keep those levels distinct in severity:

- An OKF §11 violation is a **hard failure**. The document cannot be
  interpreted, so it cannot be accepted.
- A profile deviation is an **advisory finding**: reported, attributed to the
  affected concept, and never a reason to reject a bundle that is valid OKF.

That asymmetry is deliberate. A profile that could reject valid OKF would have
made itself a competing standard, which §1.2 forbids.

Advisory findings include: missing baseline metadata; a collection holding mixed
types or subdirectories; a missing or stale index; a description that disagrees
with its concept; a broken internal link; a changed stable path; a missing,
unparseable, or disagreeing profile declaration; disallowed media under
`references/`; and a mirrored artifact with no source provenance.

**A concept without a `verified` event is not a finding.** Absence of verification is
meaningful information, not a deviation (§6.2, OKF §5.3). Tooling MUST NOT report it,
because the only way an author can clear such a report is to record a verification
that did not happen — turning a diagnostic into a corruption of the trust model.

Tooling MAY *summarize* trust tiers across a bundle, since knowing how much of a
bundle is unverified is useful. A summary is not a finding and MUST NOT affect exit
status.

### 14.2 Tolerant reading

Consumers MUST preserve OKF's tolerant-reader behaviour (OKF §11). Unknown
concept types, unknown frontmatter keys, unknown relationship labels, missing
optional content, and broken links MUST remain loadable, and unknown data MUST
remain available to downstream consumers rather than being dropped on
round-trip.

External resource availability MUST NOT be a conformance gate: a link that
404s today is a link, not a malformed document.

Valid OKF that this profile does not describe is content to carry forward
untouched — most often because it was authored by a producer outside Concepta.

### 14.3 OKF families unused by profile 0.1.0

Profile 0.1.0 uses no Attested Computation concepts (OKF §10) and defines no
convention for `runtime`, `parameters`, `computation`, `executor`, or `attester`.
This is a deliberate silence, not an oversight: Concepta has no sanctioned-value
attestation need yet.

A Concepta bundle MAY nonetheless contain such concepts — exchange across
organizations is what OKF is for — and consumers MUST treat them per OKF §10
rather than as unknown content. Should the need arise, adopting them is an
additive minor profile release (§15.2).

---

## 15. Versioning

### 15.1 Binding to OKF

Every profile release binds to **exactly one** OKF version. Profile 0.1.0 binds to
OKF 0.2.

An upstream OKF release requires a new profile release and a compatibility
review, even when no Concepta convention otherwise changes, so that a
compatibility claim is always explicit and testable. A profile release MUST NOT
claim compatibility with an OKF version it has not been reviewed against.

Because the binding is exact, references to the upstream specification SHOULD be
pinned to the commit or tag carrying that version rather than to a moving branch.

### 15.2 Profile versions

Profile versions are `<major>.<minor>`:

- A **minor** release adds backward-compatible conventions: a new collection, a
  new type, a new relationship label, an additional recommended heading, or the
  adoption of an OKF family previously unused (§14.3). A conformant bundle MUST
  NOT need changes to remain conformant.
- A **major** release makes changes that require existing conformant bundles to
  migrate.

OKF's normative requirements always take precedence over any profile release
(§1).

### Considered and deferred

Intentionally left to a later release:

- A frontmatter relationship schema, and any `x-concepta` extension namespace.
- Per-concept access control, sensitivity classification, or redaction.
- Nested collections, and cross-bundle references between repositories. Grouped
  index headings (§9) are the current answer to collection size; nesting is revisited
  only if grouping proves insufficient in practice.
- A required collection and type for open questions or known unknowns. Projects that
  need one MAY add it under §3.1.
- A convention for recording deliberately omitted content, distinct from the
  non-mirroring convention in §12.
- A normative actor-registry shape, or organizational namespacing of actor IDs. §6.1
  permits a registry; its structure is not specified, and namespacing would belong
  upstream with OKF §7.
- Adoption of Attested Computation (§14.3).
- Automatic projection between concepts and execution records in either
  direction.
- A distribution mechanism for the profile itself — package, plugin, or
  repository. Whatever is chosen MUST NOT alter OKF compatibility.

### Change record

Amendments made in place while the profile remains **Proposed**. Every change is
additive or relaxing, so a bundle conformant before them stays conformant (§15.2), and
the declared version is unchanged. Once the profile is ratified, changes of this kind
require a minor release.

| Change | Sections | Driver |
| --- | --- | --- |
| Absence of `verified` is a signal, not a deviation | §1.3, §6.2, §14.1 | Advisory pressured authors toward unperformed verifications |
| `rules` collection and `Business Rule` type added, formalism-neutral | §3, §3.1, §5.2 | Standing business rules had no home |
| `Part of` relationship label added | §7.2 | No composition label; `Related to` carried 40% of edges |
| `Partially resolves` added; `Resolves` narrowed to full closure | §7.2 | Evidence usually narrows an open item without closing it |
| Assessing the subject placed in the body — no field, not derived from links | §1.3, §6.3, §6.3.1 | Silence invited a custom maturity field, which OKF §5.1 refuses |
| OKF §5 provenance mechanisms surfaced; optional actor registry | §1.3, §6.1 | A one-line summary hid scope descriptors and derived tiers |
| Concept fission guidance added | §4.2.1 | Promotion was specified; splitting a grown concept was not |
| `adr` versus `decisions` guidance; Business Rule distinguished from Decision | §3.1 | "Architectural or not" was too thin to act on |
| Grouped index headings recommended above ~20 entries | §9 | OKF §8 permits grouping; the profile did not mention it |
| Non-mirroring recorded via scope descriptor | §12 | Deciding against mirroring is durable and had no convention |
| Collection named `analyses` consistently; stray comment removed | §3 | Tree disagreed with the §3.1 table and §8.1 IDs |
| Companion implementation specification marked not-yet-written | §Adoption note | Referenced as though it existed |
| Grouping keyed to `tags`/`status`; `references/` subdirectories indexed | §3.2, §9 | Two MUSTs named no field and no scope |
| `sources[].resource` scope-descriptor exemption scoped; `status` default noted | §6.1, §6.3 | Both read as broader than OKF §6.2 and §5.4 allow |

---

## Appendix A: Worked example

One bundle showing the profile's central separation: a **source event** produces
**durable knowledge**, which links to an **execution record**, with **indexes and
a log** as projections. A client raises a request during a demo; the recording
platform expires in 30 days, so the transcript is mirrored; an analysis follows;
the request is specified in GitHub.

```text
knowledge/
  index.md
  log.md
  profile.md
  requests/index.md, include-pdf-annotations.md
  analyses/index.md, pdf-export-feasibility.md
  references/index.md, 2026-07-30-reporting-demo-transcript.md
```

The demo itself is not a concept, and no Interaction Record was written: only one
outcome mattered, so the request links straight to its source (§4.3).

`requests/include-pdf-annotations.md` — the durable outcome, verified by a human,
citing the mirrored transcript, and linked to execution:

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
    author: human:chris
    last_modified: 2026-07-30
---

# Request

Reviewer annotations must appear in the exported PDF, positioned as they are on
screen.[^demo-0730]

# Context

Raised while reviewing a draft export during the reporting demo.

# Relationships

- Specified by: [Annotation export spec](https://github.com/conceptadev/example/issues/128)
- Related to: [PDF export feasibility](/analyses/pdf-export-feasibility.md)

[^demo-0730]: Reporting demo transcript, 30 July 2026
```

`analyses/pdf-export-feasibility.md` — a separate concept because findings are
reusable independently of the request, with a real freshness horizon (§6.4):

```markdown
---
type: Analysis
title: PDF export feasibility for annotations
description: Whether the current renderer can place annotations without exceeding the generation budget.
status: stable
generated: { by: claude-code/opus-5, at: 2026-07-31T11:00:00Z }
stale_after: 2026-10-31
---

# Question

Can annotations be positioned in the exported PDF within the existing
generation budget?

# Findings

The renderer exposes absolute placement; annotation geometry is already
persisted alongside review state.

# Recommendation

Proceed. Budget headroom is adequate at current document sizes.

# Relationships

- Refines: [Include PDF annotations in the export](/requests/include-pdf-annotations.md)
```

`references/2026-07-30-reporting-demo-transcript.md` — mirrored because the
recording expires; a snapshot, not knowledge (§12):

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
    last_modified: 2026-07-30
---

# Transcript

[15:02] ...
```

`log.md` — lifecycle events only. The demo appears nowhere; its outcomes do:

```markdown
# Knowledge Log

## 2026-07-31
* **Creation**: Recorded [PDF export feasibility](/analyses/pdf-export-feasibility.md).
* **Update**: Verified [Include PDF annotations in the export](/requests/include-pdf-annotations.md).

## 2026-07-30
* **Creation**: Recorded [Include PDF annotations in the export](/requests/include-pdf-annotations.md) from the reporting demo.
* **Creation**: Mirrored the [reporting demo transcript](/references/2026-07-30-reporting-demo-transcript.md).
```

Reading the bundle back out: the graph (§13) has three internal nodes, one
provenance edge from the request to the transcript, two typed edges
(`Refines`, `Related to`), one external node for the GitHub issue via
`Specified by`, and one external node for the expiring recording. Delete the
graph and every edge above rebuilds from these files.
