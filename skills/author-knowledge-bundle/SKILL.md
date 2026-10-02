---
name: author-knowledge-bundle
description: Create, edit, move, deprecate, or mirror content in the knowledge bundle at knowledge/ per Bitwild OKF Profile 2026.3 (OKF 0.2). Use before any write under knowledge/ — including creating a directory there — when asked to review bundle changes or produce a Profile Review Report, or when another skill needs Profile conventions.
---

# Authoring the knowledge bundle

The knowledge bundle at `knowledge/` is an Open Knowledge Format (OKF) bundle following the Bitwild OKF Profile release that project-root `wayfinder.json` selects. The profile is a thin layer on **OKF 0.2**, which is authoritative: it says *which* knowledge is worth storing, *where* it goes, and *how* concepts link, and it defines no file type and never changes an OKF field's meaning. Its one frontmatter key, `relationships`, is an additional producer key OKF §4.1 permits. Nothing here overrides the [OKF specification](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/ad30107c31c06aec8a7d5636e0d1058118604e6f/SPEC.md), pinned to the 0.2 commit and vendored at [references/OKF-0.2.md](./references/OKF-0.2.md).

`knowledge/` is the default adoption path. When a project explicitly asks to
author another configured bundle, substitute that bundle's path throughout
this workflow and resolve **its** binding. Do not apply `knowledge/`'s binding
to a sibling bundle or to an arbitrary subdirectory.

## Release dispatch

Before applying Profile rules, resolve the bundle's exact release:

- If project-root `wayfinder.json` has exactly one `applies_to` entry for
  the requested bundle, read that entry's direct `source` and any additive
  `extends` chain. The configured `bitwild-profile` package at
  `profiles/bitwild/wayfinder-profile.json` carries the vocabulary and rules,
  fetched by `wayfinder get`. A child package may add vocabulary and rules of
  its own, whose rules only add findings in the child's namespace. The routed
  concept reference carries its standard vocabulary for standalone skill
  installations. The root index
  declares OKF 0.2. Read the exact source revision from the current
  `wayfinder.lock` and local cache. If absent or stale during authorized
  authoring, run `wayfinder get` and include the resulting lock; `validate`
  itself never fetches or writes it. Use `upgrade` only for an intentional
  mutable-ref advance. If the source cannot be resolved, report that the
  release cannot be assessed rather than guessing from the entry key.
- Otherwise the bundle has no release. Validation reports
  `wayfinder/config-missing` when no `wayfinder.json` sits above the bundle,
  `wayfinder/bundle-unbound` when one exists but does not list it, and
  `wayfinder/config-invalid` when it cannot be read. A file inside the bundle
  never selects a release.
- An absent, unreadable, or unsupported selection prevents contextual review.
  Run read-only validation for its independent OKF result and diagnostic;
  never guess or silently apply a release. A 2026.2 bundle, which declared its
  release inside the bundle, must migrate to `wayfinder.json` or be validated
  with wayfinder 0.1.x.

Changing a bundle's release is migration work, not an incidental repair.
Read implementation guide §5 and the Profile's §15.3 migration impact before
migrating. Do not simply change a selector:
move the custom vocabulary and actor lookup to JSON, remove the three legacy
root concepts, regenerate every index with `wayfinder validate --fix`, and
review the result.

**Configuration stays outside the bundle.** `wayfinder.json` is configuration,
not a concept, and the bundle carries no root registry concepts. The binding
supplies custom type, tag, relationship-name, and actor declarations while the
selected base Profile supplies standards. Typed relationships are the
`relationships` frontmatter key, not a `# Relationships` body section. The
subject-placement rule and the fixed names `architecture/`, `ways-of-working/`,
`interactions/`, `references/` remain, and `computations/` joins them as the
optional OKF §10.4 home for Attested Computation concepts. Every index is the output of okf's reference
index generator, written by `wayfinder validate --fix`. A binding applies to a
whole bundle, never an area.

**Where this skill is silent, OKF 0.2 governs.** Silence means the upstream spec already settles the point, so read it and follow it — never invent a local Profile convention to fill a gap. See [Beyond this profile](#beyond-this-profile) for what that covers in practice. Within what the profile *does* specify, concepts take the shapes taught in the references below and never invented ones.

## Route by operation

Read the reference covering the write before making it. One operation commonly
touches several — a new concept in a new directory needs the first two at least.

| Doing | Read first |
| --- | --- |
| Creating or editing a concept — capture bar, types, frontmatter, provenance, execution links | [references/concept-authoring.md](./references/concept-authoring.md) |
| Creating or naming a directory, placing a concept, moving, deprecating, deleting | [references/structure-and-lifecycle.md](./references/structure-and-lifecycle.md) |
| Creating or regenerating an `index.md` — every write touches at least one | run `wayfinder validate <bundle> --fix` |
| Giving links a typed meaning with `relationships` frontmatter | [references/relationships.md](./references/relationships.md) |
| Mirroring external material into `references/` | [references/source-mirroring.md](./references/source-mirroring.md) |
| Profile Review — after any write, or when asked | [references/profile-assessment.md](./references/profile-assessment.md) |
| Changing the configured release, or converting an existing tree | not this skill — see [Release dispatch](#release-dispatch) |
| Seeding a new bundle from nothing | the [`adopt-knowledge-bundle` skill](../adopt-knowledge-bundle/SKILL.md) |
| Anything the profile says nothing about | [references/OKF-0.2.md](./references/OKF-0.2.md) |

## The atomic bundle write

Every write follows this sequence, and is complete only when all of it exists:

1. The concept file, conforming to the routed references above.
2. Every affected `index.md`. Run `wayfinder validate <bundle> --fix`: it writes okf's generated indexes, then validates. Never hand-edit an index; a hand edit is drift.
3. Its authored `knowledge/log.md` entry — under today's `## YYYY-MM-DD` heading (newest first): `* **Creation**: …`, `* **Update**: …`, `* **Deprecation**: …`, or another nonempty bold lead word followed by a colon. Log meaningful lifecycle events only, never formatting edits. The log is history, not a projection.
4. Automated validation, when `wayfinder validate` is available: run it over the whole bundle and repair deterministic failures before finishing.
5. Scoped Profile Review per [references/profile-assessment.md](./references/profile-assessment.md), with its report emitted in the active interaction or pull request.

Complete the affected indexes, any required lifecycle log entry, and review
before finishing. Formatting-only changes do not need a log entry.

## Beyond this profile

The profile constrains a subset of OKF and leaves the rest alone. When you need something this skill doesn't cover, the answer is in [references/OKF-0.2.md](./references/OKF-0.2.md) — the pinned spec, vendored so it is readable without a network fetch. Read it and follow it; do not invent a convention, and do not assume the omission means the mechanism is unavailable.

What the profile deliberately says little or nothing about:

| Look up | OKF § |
| --- | --- |
| **Attested Computation** — `runtime`, `parameters`, `computation`, `executor`, `attester`, the `# Computation` heading, and how a consumer executes and attests | §10 |
| **`usage_count` and `usage_window`** — adoption and liveness signals on a source, and why they read as trend rather than score | §5.1 |
| **Lineage through links** — recursing into a source that is itself a concept, so credibility propagates without a `derived_from` field | §5.1 |
| **Conventional body headings** `# Schema` and `# Examples` | §4.2 |
| **`resource`** as the canonical URI of the asset a concept describes | §4.1, §6.2 |
| **Tag-based views**, synthesized at consumption time rather than stored as files | §3.1 |
| **v0.1 fallbacks** — legacy `timestamp` and body `# Citations` in inherited bundles | §13 |

Two rules govern the gap. Silence is **deference**, so a question the profile does not answer is answered upstream and following OKF there is correct, not a deviation. Silence is **not prohibition**, so a mechanism OKF permits and the profile never mentions is permitted. The profile's actual narrowings are stated as such in the references: no frontmatter fields beyond OKF's and the release's declared `relationships`, no kind-named directories, `status` as knowledge lifecycle only, and indexes that are okf's generated output.
