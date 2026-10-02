---
name: author-knowledge-bundle
description: Create, edit, move, deprecate, or mirror content in an OKF knowledge bundle that a project's wayfinder.json binds to a Profile, at knowledge/ by default. Use before any write under the bundle, including creating a directory there, when asked to review bundle changes or produce a Profile Review Report, or when another skill needs the bundle's conventions.
---

# Authoring the knowledge bundle

The knowledge bundle is an Open Knowledge Format (OKF) bundle, at `knowledge/`
unless the project says otherwise. OKF is authoritative. The project-root
`wayfinder.json` binds the bundle to a Profile, and that Profile may build on
parents. Each Profile in the chain adds two things on top of OKF:

- rules in its package, which `wayfinder validate` enforces;
- judgment in its skill, which `wayfinder get` installs into the project.

This skill owns the OKF mechanics and the write sequence. The Profile skills
own every convention beyond OKF. When a project asks you to author another
bundle, substitute its path throughout and use its own binding. Never apply
one bundle's binding to a sibling bundle or to a subdirectory.

## Load the Profile chain

Before writing, find the Profiles that govern the bundle:

```bash
wayfinder validate knowledge --output json | jq -r '.profile.chain[].id'
```

The chain is root first. For each id, read `.claude/skills/<id>/SKILL.md`, or
`.agents/skills/<id>/SKILL.md` when only that copy exists, in chain order. A
later Profile adds to an earlier one and never relaxes it. Follow each skill's
routing for the write at hand.

When the chain cannot be read, act on the diagnostic `validate` reports:

- `wayfinder/config-missing`, `wayfinder/bundle-unbound`, or
  `wayfinder/config-invalid`: the bundle has no usable binding. Do not guess a
  Profile. Contextual review cannot run; report that.
- `wayfinder/profile-unresolved`: the lock is missing or stale. During
  authorized authoring, run `wayfinder get` and include the resulting
  `wayfinder.lock` and skill directories in the change. Otherwise report it.
  `validate` itself never fetches.
- `wayfinder/profile-skill-stale`, or a chain id with no installed skill
  directory although its package ships one: run `wayfinder get`, which
  installs the skill pinned to the locked commit. Never edit an installed
  Profile skill by hand; `get` replaces it.

A chain member that ships no skill adds rules but no judgment. Its findings
still apply.

Changing which Profile or release a bundle uses is migration work, not an
incidental repair. Do it only when asked, following the Profile's own
migration guidance and its changelog. Use `wayfinder upgrade` only for an
intentional advance of a mutable ref.

## Route by operation

Read the routed material before making the write. One write often touches
several rows.

| Doing | Read first |
| --- | --- |
| Creating or editing a concept: frontmatter, sources, links | [references/okf-authoring.md](./references/okf-authoring.md), then each Profile skill's routing |
| Creating a directory, placing, naming, moving, deprecating, deleting, mirroring | each Profile skill's routing |
| Creating or regenerating an `index.md`; every write touches at least one | run `wayfinder validate <bundle> --fix` |
| Profile Review, after any write or when asked | [references/profile-assessment.md](./references/profile-assessment.md) |
| Seeding a new bundle | the [`adopt-knowledge-bundle` skill](../adopt-knowledge-bundle/SKILL.md) |
| Anything no Profile skill covers | [references/OKF-0.2.md](./references/OKF-0.2.md) |

## The atomic bundle write

A write is complete only when all of these exist:

1. The concept file, following OKF and every Profile skill in the chain.
2. Every affected `index.md`. Run `wayfinder validate <bundle> --fix`. It
   writes okf's generated indexes, then validates. Never edit a generated
   index by hand.
3. A `log.md` entry for a lifecycle event, under today's `## YYYY-MM-DD`
   heading, newest first, as `* **<Lead word>**: <what changed>`. The Profile
   skills say which events to log. A formatting-only change needs no entry.
4. A passing `wayfinder validate <bundle>` over the whole bundle. Repair
   deterministic failures before finishing.
5. A scoped Profile Review per
   [references/profile-assessment.md](./references/profile-assessment.md),
   with its report in the interaction or pull request.

## Where the Profile skills are silent

Follow OKF. The vendored [OKF 0.2 specification](./references/OKF-0.2.md)
is readable without a network fetch. Silence is deference: a question no
Profile answers is answered upstream, and following OKF there is correct.
Silence is not prohibition: a mechanism OKF permits and no Profile mentions is
permitted. Never invent a convention to fill the gap.

OKF mechanisms a Profile often leaves alone:

| Look up | OKF § |
| --- | --- |
| Attested Computation: `runtime`, `parameters`, `computation`, `executor`, `attester`, the `# Computation` heading, and how a consumer executes and attests | §10 |
| `usage_count` and `usage_window` on a source, read as trend rather than score | §5.1 |
| Lineage through a source that is itself a concept | §5.1 |
| Conventional body headings `# Schema` and `# Examples` | §4.2 |
| `resource` as the canonical URI of the asset a concept describes | §4.1, §6.2 |
| Tag-based views, synthesized when reading rather than stored | §3.1 |
| v0.1 fallbacks: `timestamp` and body `# Citations` in inherited bundles | §13 |
