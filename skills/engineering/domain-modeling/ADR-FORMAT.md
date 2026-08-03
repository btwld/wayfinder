# ADR Format

ADRs are `Architecture Decision Record` concepts in `knowledge/architecture/`, numbered `0001-slug.md`, `0002-slug.md`, … Scan the directory for the highest existing number and increment by one. An ADR arriving from somewhere else keeps the number it already had: an identifier other systems cite is part of identity and is never reassigned (profile §8.1). Create `architecture/` lazily — only when the first ADR or Architecture Document is needed.

They live in `architecture/` because an ADR's subject is the system being built; `Architecture Decision Record` is its type, not its folder. Reading the ADR set as a set is an index filtered by type.

## Template

```markdown
---
type: Architecture Decision Record
title: <Short title of the decision>
description: <One sentence: what was decided.>
status: <draft while proposed, stable once accepted>
generated: { by: <actor>, at: <ISO 8601 datetime> }
---

<1-3 sentences: what's the context, what did we decide, and why.>
```

An ADR can be a single paragraph. The value is in recording *that* a decision was made and *why* — not in filling out sections.

`status` carries the lifecycle: `draft` while proposed, `stable` once accepted, `deprecated` when retired or superseded — link the successor under `# Relationships` with `Superseded by`.

## Optional sections

Only include these when they add genuine value. Most ADRs won't need them: `# Context`, `# Decision`, `# Consequences`, `# Alternatives considered`, `# Relationships`.

## What qualifies

The three gating criteria live in the skill (hard to reverse, surprising without context, a real trade-off). Decisions that typically pass them:

- **Architectural shape.** "We're using a monorepo." "The write model is event-sourced, the read model is projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target. Not every library — just the ones that would take a quarter to swap out.
- **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no-s are as valuable as the yes-s.
- **Deliberate deviations from the obvious path.** "We're using manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite — these stop the next engineer from "fixing" something that was deliberate.
- **Constraints not visible in the code.** "We can't use AWS because of compliance requirements." "Response times must be under 200ms because of the partner API contract."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it — otherwise someone will suggest GraphQL again in six months.

Durable decisions that fail the architectural criteria but still need their own lifecycle become `type: Decision` instead, filed in the area of whatever the decision is about.

Architecture scoped to a single capability is that capability's knowledge, not the system's: a data model for billing belongs in the billing area with `type: Architecture Document`. Only system-wide structure, technology, and boundaries live in `architecture/`.
