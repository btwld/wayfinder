# Concept authoring

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply. This reference covers what earns a concept, its
type, its frontmatter, its provenance, and its link to execution records.

## What earns a concept

A source event is an activity: a daily, planning session, demo, call, or conversation. It **never** becomes a concept merely because it happened. An artifact the event produced, such as a transcript, may be mirrored as an ordinary source concept when the mirroring rule applies ([source-mirroring.md](./source-mirroring.md)). An interpreted concept is earned when the event produced durable knowledge: a meaningful request, decision, investigation and findings, architectural constraint, term, standing rule, named unknown, or reusable guidance. An event that produced none leaves no interpreted outcome behind, and that is correct rather than a gap — the bar keeps the bundle from degenerating into routine minutes.

Requests are ordinarily first-class: a request outlives the conversation that expressed it and can later be analyzed, specified, implemented, rejected, or superseded, which is a lifecycle of its own.

**Promotion is decided by identity, not importance.** The Profile recommends promotion when an outcome needs independent status, provenance, relationships, reuse, replacement, or history; genuine boundary cases may stay embedded. Given an outcome — a decision, an answer, an unknown — ask whether it has a lifecycle outside the concept where it arose:

- **Normally keep it embedded** when it has no meaningful identity of its own. A small outcome that will never be referenced, verified, or superseded on its own can stay where it arose, as a heading in that concept's body.
- **Prefer its own concept** when it needs independent status, provenance, relationships, reuse, replacement, or history.

An ambiguous outcome should normally start embedded, because un-promoting it is free until something outside the bundle cites its path. The same test decides a `Question`: a named unknown with an evidence trail, several dependents, or an ID cited outside the bundle is normally a concept; a single unknown belonging to one concept, with nothing recorded but the gap itself, can remain a heading in that concept's body.

An **Interaction Record** is the narrower case of the same rule: write one only when an interaction's *combined* context is itself durable — several linked outcomes, a negotiation, a demo whose overall shape matters. When one outcome mattered, normally link that outcome straight to its external source; no Interaction Record is required. Never produce one as routine minutes.

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
the concept has labelled links ([relationships.md](./relationships.md)).

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

- Add `generated` when the producer and meaningful-change time are known. It is recommended, not required; never fabricate either value to clear an advisory. Write it in the block style Profile §6.5 asks for:

  ```yaml
  generated:
    by: <actor>
    at: "<ISO 8601 datetime with a UTC offset>"
  ```
- **Every timestamp is an instant, and the offset is not optional** (Profile §6.5, OKF §5). `generated.at`, `verified[].at`, `stale_after`, `sources[].last_modified` and `usage_window` all take an ISO 8601 datetime with an explicit UTC offset; a date-only value names no instant and raises the `okf/timestamp-without-offset` advisory. When a source is known only to the day, write `T00:00:00Z` and mean it. Quote timestamps so YAML carries the authored text, write structured values in block style rather than inline `{…}`, and write `verified` as a list even with one entry. These bind what you write — keep reading every spelling OKF permits, because the specification's own examples use the inline forms. `okf format --migrate-timestamps` converts an existing bundle.
- **Status** is knowledge lifecycle only — `draft`, `stable`, `deprecated`. Workflow states (accepted, blocked, in progress, done) belong to the issue tracker.
- Add native OKF fields (`tags`, `resource`, `stale_after`) when their OKF-defined meaning applies. `sources` and `verified` have their own section below.
- **`tags` carry topic and nothing else** — never kind (that is `type`), lifecycle (`status`), trust (derived from `verified`), or a judgment about how settled the subject is (body prose). A tag restating one of those is redundant when written and wrong once the real signal moves: `partially-resolved` on a question is a fact about an inbound edge, and nothing updates it when a second edge lands.
- Concepta producers write only OKF-defined fields. Readers still preserve unknown fields and keep the concept loadable, because the producer restriction does not change OKF's tolerant-reader contract.

## Provenance and trust

Read OKF §5 before writing provenance or trust fields; it owns their syntax and
meaning. The Concepta delta is narrower:

- When a claim materially derives from identifiable source material, record that material with OKF `sources`; original analysis, guidance, and decisions do not invent sources just to satisfy the rule. Profile Review judges whether material provenance is missing, while tools check only present source structure and attribution joins.
- Keep production and confirmation distinct. A meaningful rewrite during authoring or migration can truthfully update `generated` without verifying any claims; the field remains recommended, not required. Add `verified` only when the named actor actually confirmed content against its sources or `resource`. Review, migration, or conformance work alone is not that confirmation.
- **Absence of `verified` is a signal, not a defect.** A concept deliberately recording unconfirmed material is *correctly* unverified. Never add a verification event to satisfy a convention, a checklist, or a linter; tooling must not report missing verification as a finding.
- **Organizational identity is not in the tier.** Trust tiers distinguish human from machine, not client from internal. That distinction lives in `knowledge/actors.md`, whose `Side` is exactly `client`, `internal`, `vendor`, `tool`, or `unknown`. Never guess an affiliation: use `unknown`. `Active` is `YYYY-MM-DD – YYYY-MM-DD` (start inclusive, end exclusive), `YYYY-MM-DD –`, or `unknown`; repeated rows for one ID must not overlap. Resolve `generated` and `verified` at their event timestamps, and a source author at `last_modified` when available; otherwise affiliation stays unknown. A third-party authoring agent is `tool`; a process the project itself runs is `internal`. Never encode affiliation into an actor ID — `human:acme/jane-doe` puts a mutable attribute inside an immutable key and forces a rewrite when it changes. Registry lookup never changes the actor string, its OKF prefix, or its derived trust tier.
- Never invent a maturity, confidence, credibility, or evidence-tier frontmatter field. Use the upstream signals and attribution mechanism without restating or extending them.

- **How settled the *subject* is belongs in the body, not in frontmatter and not in `status`.** `status` describes the document — OKF's `draft` means "not yet reviewed". State the assessment beside the reasoning that justifies it, with pointers to what would settle it. A shared vocabulary is optional; if adopted, it should be defined once in a `ways-of-working/` concept. It is **not derivable from links**: `Constrained by` may target a fully settled constraint, broken links are valid, and absence of links is silence rather than evidence. A concept can be first-party, verified, and still describe an unsettled subject.
- **Freshness needs evidence.** Add `stale_after` only when the content has a real horizon supported by evidence, never as a default for a type or as a conformance placeholder.

## Execution stays external

Tickets, issues, and PRs live in the issue tracker. Concepts link to them (`Specified by`, `Implemented by`) — the bundle never mirrors their state, and a linked record's status lives only in the tracker.
One concept may link to several execution records or none; cardinality alone is
never a finding.

**"Specification" is a genre, not a location.** What makes something an execution record is that a tracker owns its state — a status, an assignee, a workflow the bundle does not advance. A spec opened as a GitHub issue is an execution record: link it, never mirror it. A spec the project maintains as durable knowledge — it outlives the work it scoped, later concepts cite it, and its only state is `status` — is a `Specification` concept, filed with its subject like anything else. Every durable specification has exactly one lifecycle owner. Never both: one artifact, one home.
