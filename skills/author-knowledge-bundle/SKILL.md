---
name: author-knowledge-bundle
description: Create, edit, move, deprecate, or mirror content in the knowledge bundle at knowledge/ per Concepta OKF Profile 2026.2 (OKF 0.2). Use before any write under knowledge/ — including creating a directory there — when asked to review bundle changes or produce a Profile Review Report, or when another skill needs Profile conventions.
---

# Authoring the knowledge bundle

The knowledge bundle at `knowledge/` is an Open Knowledge Format (OKF) bundle following the Concepta OKF Profile — versions declared in `knowledge/profile.md`. The profile is a thin layer on **OKF 0.2**, which is authoritative: it says *which* knowledge is worth storing, *where* it goes, and *how* concepts link, and it defines no file type, no frontmatter field, and no metadata semantics of its own. Nothing here overrides the [OKF specification](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/ad30107c31c06aec8a7d5636e0d1058118604e6f/SPEC.md), pinned to the 0.2 commit and vendored at [references/OKF-0.2.md](./references/OKF-0.2.md).

## Release dispatch

Before applying Profile rules, read the first fenced `yaml` block in the body of
`knowledge/profile.md`. Dispatch on `concepta_profile`: this skill implements
only `"2026.2"`, which binds to OKF `"0.2"`.

- A supported Profile selector with a wrong `okf_version` or disagreement with
  the root index is a **binding defect**, not an unsupported release. Report the
  automated diagnostics and repair only what the available evidence and requested
  scope justify; do not infer a different intended release.
- An absent or unreadable selector prevents dispatch. Report the declaration
  problem rather than guessing a release.
- An unsupported selector prevents authoring and contextual Profile Review under
  these rules. Report which release is unsupported; a matching skill or an explicit
  migration is needed for that work. Do not silently apply 2026.2.

Read-only automated validation remains available in all three cases: its independent
OKF result and release diagnostics are useful even when contextual review cannot
proceed. Do not suppress those results or confuse unsupported capability with
nonconformance. Generic OKF reading remains available.
The declaration is only a release selector: never turn `profile.md` into a
standalone definition, extension registry, second schema, or OKF override.

**Where this skill is silent, OKF 0.2 governs.** Silence means the upstream spec already settles the point, so read it and follow it — never invent a Concepta convention to fill a gap. See [Beyond this profile](#beyond-this-profile) for what that covers in practice. Within what the profile *does* specify, concepts take the shapes taught in the references below and never invented ones.

## Route by operation

Read the reference covering the write before making it. One operation commonly
touches several — a new concept in a new directory needs the first two at least.

| Doing | Read first |
| --- | --- |
| Creating or editing a concept — capture bar, types, frontmatter, provenance, execution links | [references/concept-authoring.md](./references/concept-authoring.md) |
| Creating or naming a directory, placing a concept, moving, deprecating, deleting | [references/structure-and-lifecycle.md](./references/structure-and-lifecycle.md) |
| Creating or regenerating an `index.md` — every write touches at least one | [references/index-projection.md](./references/index-projection.md) |
| Giving links a labelled meaning in `# Relationships` | [references/relationships.md](./references/relationships.md) |
| Mirroring external material into `references/` | [references/source-mirroring.md](./references/source-mirroring.md) |
| Profile Review — after any write, or when asked | [references/profile-assessment.md](./references/profile-assessment.md) |
| Seeding a new bundle from nothing | the [`adopt-knowledge-bundle` skill](../adopt-knowledge-bundle/SKILL.md) |
| Anything the profile says nothing about | [references/OKF-0.2.md](./references/OKF-0.2.md) |

## The atomic bundle write

Every write follows this sequence, and is complete only when all of it exists:

1. The concept file, conforming to the routed references above.
2. Every affected `index.md`, rewritten as the deterministic projection defined in [references/index-projection.md](./references/index-projection.md). Nothing generates indexes for you — follow that reference exactly.
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

Two rules govern the gap. Silence is **deference**, so a question the profile does not answer is answered upstream and following OKF there is correct, not a deviation. Silence is **not prohibition**, so a mechanism OKF permits and the profile never mentions is permitted. The profile's actual narrowings are stated as such in the references: no custom frontmatter fields, no kind-named directories, `status` as knowledge lifecycle only, an `index.md` in every nonempty directory with descriptions copied verbatim.
