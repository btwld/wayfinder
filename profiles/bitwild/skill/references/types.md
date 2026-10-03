# Types and body shapes

`type` is the only place a concept's kind lives. The directory, the filename,
and the tags never carry it.

## Standard types

The Profile package declares these types. A project adds its own in its
`wayfinder.json` entry under `types`.

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
| `Attested Computation` | An OKF-defined sanctioned computation with a checkable execution receipt |

`Attested Computation` takes its contract from OKF §10, not from this
Profile.

## Choose between neighbours

The type must match its intended meaning. A project type must match the
meaning its `wayfinder.json` entry declares. Decide the fit from the
concept's content, never from headings, paths, or keywords.

- Use `Architecture Decision Record` when the decision shapes the software's
  structure and an engineer deciding how to build would read it. Use
  `Decision` for every other durable decision: process, commercial, scope, or
  governance. When both fit, prefer `Decision`.
- A `Business Rule` is not a `Decision`. A rule describes how the business
  already works. A decision records a choice between alternatives.
- When a rule turns out to be a policy a Decision selected, give the rule a
  `depends-on` relationship to that Decision.
- A `Business Rule` holds one standing rule. It commits to one rule per
  concept, not to a notation, so SBVR or any notation the domain suits is
  fine.
- A `Question` carries no state in its type or its path. Read openness from
  inbound relationships: `resolves` means closed, `partially-resolves` means
  narrowed, and neither means open. A resolved question stays `stable`,
  because how understanding reached an answer is knowledge too.

## Project types

A project type is allowed once its `wayfinder.json` entry declares it.
Validation reports each declared project type as the `wayfinder/project-type`
note, so repeated needs can inform a later release. Do not reject a project
type because a standard type might also fit. When reading, preserve unknown
types, fields, and relationship names. Valid OKF you do not recognize is
content, not an error.

## Starting headings

Use only the headings that help the concept. These shapes are prompts, not
conformance rules. Omit, rename, or add headings as the knowledge requires.

| Type | Starting headings |
| --- | --- |
| Request | Request, Context, Constraints |
| Decision, Architecture Decision Record | Context, Decision, Consequences |
| Analysis | Question, Findings, Recommendation |
| Glossary Definition | Definition, Avoid |
| Business Rule | Rule, Rationale, Consequences |
| Question | Question, What is known, Still missing, What would close it |

Typed links go in the `relationships` frontmatter key
([relationships.md](relationships.md)), never in a `# Relationships` body
section.
