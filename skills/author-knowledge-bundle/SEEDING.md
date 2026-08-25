# Seeding a bundle

The root files of a new bundle at `knowledge/`. Replace `<...>` placeholders;
`generated.by` follows the [OKF §7 actor convention](./OKF-0.2.md#7-actor-convention).

The structural minimum is `index.md`, `log.md`, `profile.md`, and `types.md`.
These templates also use `generated.by`, so their literal seeded form requires
`actors.md` and represents that actor. Seed these five and nothing else. **Do not
create areas up front** — generic setup has no corpus from which to judge a shared
subject. A genuine area may later be any size; the actual knowledge, not a numeric
threshold, must justify it.

## `knowledge/index.md`

````markdown
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
* [Concepta OKF Profile](profile.md) - Declares the Concepta profile and OKF versions this bundle follows.
* [Types](types.md) - The standard and project-specific types available to this bundle.
* [Actors](actors.md) - Actor IDs mapped to identity, affiliation, role, and active period.
````

Other root concepts are grouped under their exact registered `type`. Immediate
directories are listed under `# Directories` with their final path segment as the
label and no description. The root `Bundle` entries remain in the order shown.

## `knowledge/log.md`

````markdown
# Knowledge Log

## <YYYY-MM-DD>
* **Initialization**: Established the knowledge bundle under the Concepta OKF Profile 2026.2.
````

## `knowledge/profile.md`

````markdown
---
type: Knowledge Profile
title: Concepta OKF Profile
description: Declares the Concepta profile and OKF versions this bundle follows.
status: stable
generated: { by: <actor>, at: <ISO 8601 datetime> }
---

This bundle follows the Concepta OKF Profile. The block below is the
machine-readable declaration; tools read exactly this block.

```yaml
concepta_profile: "2026.2"
okf_version: "0.2"
```

OKF is authoritative: when the profile and OKF differ, OKF wins.
````

`concepta_profile` and `okf_version` mean different things — the profile release,
and the OKF version it binds to. Their **formats** differ so they can never be
confused: the profile uses `<year>.<serial>` (`2026.2`), OKF uses
`<major>.<minor>` (`0.2`). Copy both verbatim; don't derive one from the other.
## `knowledge/types.md`

Seed all fourteen standard types in the canonical order below, including unused
types. Add project-specific types after them in case-sensitive lexical order before
first use.

````markdown
---
type: Type Registry
title: Types
description: The standard and project-specific types available to this bundle.
status: stable
generated: { by: <actor>, at: <ISO 8601 datetime> }
---

Every concept's `type` resolves here. Kind is carried by `type` alone, never by a
directory name. Standard rows stay present even when unused; add an extension row
before using a project-specific type.

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
````

## `knowledge/actors.md`

Required whenever any concept uses `generated.by`, `verified[].by`, or
`sources[].author`. These literal templates use `generated.by`, so the seeded bundle
includes the registry and the actor below.

````markdown
---
type: Actor Registry
title: Actors
description: Actor IDs mapped to identity, affiliation, role, and active period.
status: stable
generated: { by: <actor>, at: <ISO 8601 datetime> }
---

Actor IDs are opaque and stable: affiliation is looked up here, never encoded into
the ID. Someone who changes organization gets a new non-overlapping row range, so
historical attributions resolve at event time. An actor missing from this table reads
as unknown to a generic consumer; it never invalidates the OKF actor value, though
the missing Profile row must still be repaired.

`Side` is one of `client`, `internal`, `vendor`, `tool`, `unknown`; use `unknown`
rather than infer affiliation. `Active` is `YYYY-MM-DD – YYYY-MM-DD` with the end
exclusive, `YYYY-MM-DD –`, or `unknown`. A third-party
authoring agent is `tool`; a process the project itself runs is `internal`.

| Actor ID | Name | Organization | Side | Role | Active |
|----------|------|--------------|------|------|--------|
| `<actor>` | <Name> | <Org or unknown> | <Side or unknown> | <Role or unknown> | <YYYY-MM-DD> – |
````
