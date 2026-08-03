# Glossary Format

The bundle holds the project's ubiquitous language as one Glossary Definition concept per term, so terms can be linked, indexed, deprecated, and superseded individually. A term lives in the area whose subject it belongs to — beside the rules deriving it and the questions about it — or at the bundle root when that subject has no area yet.

## A term concept

`knowledge/<area>/<term>.md`:

```markdown
---
type: Glossary Definition
title: Invoice
description: A request for payment sent to a customer after delivery.
status: stable
generated: { by: human:chris, at: 2026-07-30T14:00:00Z }
---

# Definition

A request for payment sent to a customer after delivery.

# Avoid

- Bill
- Payment request
```

Add a `# Relationships` section (per the `okf-profile` skill) when a term relates to or supersedes another.

## Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others under `# Avoid`.
- **Keep definitions tight.** One or two sentences max. Define what it IS, not what it does. The `description` is the definition's one-line form — the area index inherits it verbatim.
- **Only include terms specific to this project.** General programming concepts (timeouts, error types, utility patterns) don't belong even if the project uses them extensively. Before adding a term, ask: is this unique to this project, or a general programming concept? Only the former belongs.

## Multiple bounded contexts

A bounded context is usually already an area, so the structure does the disambiguating. When the same word means different things in two contexts, write one concept per meaning in each context's area — `ordering/order.md` and `billing/order.md` — keeping the bare word as `title` and letting the `description` and the path disambiguate. No filename suffix, no context tag.

Where a context has fewer than three concepts it has no area yet, so its terms sit at the bundle root. If two meanings of one word collide there, that collision is the signal that at least one of those subjects is ready for its area.
