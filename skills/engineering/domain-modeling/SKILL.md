---
name: domain-modeling
description: Build and sharpen a project's domain model as OKF concepts in the knowledge bundle. Use when the user wants to pin down domain terminology or a ubiquitous language, record a decision or an ADR, or when another skill needs to maintain the domain model.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing concepts down the moment they crystallise. (Merely *reading* the glossary for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## Where the model lives

The knowledge bundle at `knowledge/` (Concepta OKF Profile — versions declared in `knowledge/profile.md`):

```
knowledge/
├── index.md          ← root index: root concepts, areas, references/
├── log.md            ← root log: one entry per concept lifecycle event
├── profile.md        ← the profile and OKF versions this bundle follows
├── types.md          ← every type the bundle uses
├── actors.md         ← every actor ID → organization, side, role
├── <concept>.md      ← a concept whose subject has not earned an area yet
├── <area>/           ← a subject directory: mixed types, its own index.md
├── architecture/     ← the system as a whole: Architecture Documents and ADRs
├── ways-of-working/  ← how the team works: process, conventions, decisions about the bundle
├── interactions/     ← Interaction Records, organized by date
└── references/       ← mirrored source material cited by concepts
```

**Directories name subjects, not kinds.** There is no `glossary/`, `decisions/`, or `adr/`: a term, the decisions about it, and the rules deriving it share a directory because they share a subject. Kind lives in `type`.

An area is earned when three concepts share its subject — until then write concepts at the bundle root, where they cost nothing to move. **Don't create a directory to hold your first term.** Read `knowledge/index.md` to find the area a subject already has. The exception is the four names the profile fixes — `architecture/`, `ways-of-working/`, `interactions/`, and `references/` — which may be created for their first concept, since a profile-fixed name can't turn out to be the wrong one.

The `okf-profile` skill owns the mechanics of every write: baseline frontmatter, path IDs, relationship labels, placement, and the area-index and root-log entries that complete a concept write. Follow it for each concept you create, update, or deprecate here.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with existing language in the bundle, call it out immediately. "The bundle defines 'cancellation' as X, but you seem to mean Y — which is it?" Existing terms are the `Glossary Definition` concepts across the areas; the root index is the way in.

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Capture terms the moment they resolve

When a term is resolved, write its Glossary Definition concept right there — one term, one concept, in the area whose subject it belongs to, or at the bundle root if that subject has no area yet. Don't batch these up. Use the format in [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md).

Glossary concepts stay devoid of implementation details. A definition is not a spec, a scratch pad, or a home for implementation decisions.

### Promote decisions by identity

A decision earns its own concept only by identity — when it needs independent status, provenance, relationships, or history. Route it:

- **`Architecture Decision Record`** when all three hold: **hard to reverse**, **surprising without context**, **the result of a real trade-off**. If any is missing, it's not an ADR. It goes in `knowledge/architecture/`, whose subject is the system. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).
- **`Decision`** for a durable non-architectural decision with an independent lifecycle — it will be referenced, verified, deprecated, or superseded on its own. Same concept mechanics; it goes in the area of whatever the decision is *about*, which is rarely the same place as the last one.
- **Embedded** everywhere else: record the outcome inside the concept where it arose. A small outcome doesn't get its own file.
