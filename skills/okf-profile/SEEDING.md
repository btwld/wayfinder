# Seeding a bundle

The root files of a new bundle at `knowledge/`. Replace `<...>` placeholders; `generated.by` uses the actor convention from [SKILL.md](./SKILL.md).

Seed these five and nothing else. **Do not create areas up front** — an area is earned when three concepts share its subject, so the first concepts sit at the bundle root and move into an area once one is earned. Moving them is cheap and does not depend on their `status`; what waiting buys is an area name that was *observed* rather than guessed. Laying out a directory tree in advance is what the profile exists to prevent.

## `knowledge/index.md`

````markdown
---
okf_version: "0.2"
---

# Bundle

* [Concepta OKF Profile](profile.md) - Declares the Concepta profile and OKF versions this bundle follows.
* [Types](types.md) - The concept types this bundle uses.
* [Actors](actors.md) - Actor IDs mapped to organization, side, and role.
````

Concepts written at the root are listed under an `# Elsewhere` heading, alongside `references/` when it exists — only the three defined root concepts sit under `# Bundle`. An area adds its own `* [Area](area/) - <subject>` line under an `# Areas` heading when it is created.

## `knowledge/log.md`

````markdown
# Knowledge Log

## <YYYY-MM-DD>
* **Initialization**: Established the knowledge bundle under the Concepta OKF Profile 2026.1.
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
concepta_profile: "2026.1"
okf_version: "0.2"
```

OKF is authoritative: when the profile and OKF differ, OKF wins.
````

`concepta_profile` and `okf_version` mean different things — the profile release, and the OKF version it binds to. Their **formats** differ so they can never be confused: the profile uses `<year>.<serial>` (`2026.1`), OKF uses `<major>.<minor>` (`0.2`). Copy both verbatim; don't derive one from the other. A bundle seeded before 2026.1 carries a semver profile value, which stays valid.

## `knowledge/types.md`

Seed only the types the bundle actually uses and add rows as it grows; the full default vocabulary is in [SKILL.md](./SKILL.md).

````markdown
---
type: Type Registry
title: Types
description: The concept types this bundle uses.
status: stable
generated: { by: <actor>, at: <ISO 8601 datetime> }
---

Every concept's `type` resolves here. Kind is carried by `type` alone, never by a
directory name. Add a row before using a new type.

| Type | Intended content |
|------|------------------|
| `Knowledge Profile` | The profile declaration |
| `Type Registry` | This registry |
| `Actor Registry` | Actor IDs mapped to organization, side, and role |
````

## `knowledge/actors.md`

Required once concepts distinguish their sources by organization; worth seeding either way, so the first `generated.by` actor is already legible.

````markdown
---
type: Actor Registry
title: Actors
description: Actor IDs mapped to organization, side, and role.
status: stable
generated: { by: <actor>, at: <ISO 8601 datetime> }
---

Actor IDs are opaque and stable: affiliation is looked up here, never encoded into
the ID. Someone who changes organization gets a new row range, so historical
attributions stay true. An actor missing from this table reads as unknown — that
degrades a lookup, it never invalidates a concept.

`Side` is one of `client`, `internal`, `vendor`, `tool`, `unknown`. A third-party
authoring agent is `tool`; a process the project itself runs is `internal`.

| Actor ID | Name | Organization | Side | Role | Active |
|----------|------|--------------|------|------|--------|
| `<actor>` | <Name> | <Org> | internal | <Role> | <YYYY-MM> – |
````
