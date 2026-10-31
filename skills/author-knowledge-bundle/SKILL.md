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

The chain is root first. It is present whenever a Profile was selected,
including when OKF fails and the Profile state is `BLOCKED BY OKF`, so you
can load the Profile skills before you repair an OKF error. For each id,
read `.claude/skills/<id>/SKILL.md`, or
`.agents/skills/<id>/SKILL.md` when only that copy exists, in chain order. A
later Profile adds to an earlier one and never relaxes it. Follow each skill's
routing for the write at hand.

Read `profile.state` for the assessment state: without a chain, it can be
`NOT ASSESSED` or `BLOCKED BY OKF` when OKF fails without a selected Profile.
Never guess a Profile or its rules. Diagnose:

| Diagnostic | Action |
| --- | --- |
| `config-missing`, `bundle-unbound`, `config-invalid` | Report unusable binding; contextual review cannot run. |
| `profile-unresolved` | During authorized authoring, run `get` and include lock/skills; otherwise report. Validation never fetches. |
| `profile-invalid`, `profile-unsupported`, `profile-timeout`, `profile-composition` | No rule ran. Report; unsupported needs a matching engine or package migration, composition may need project additions repaired, invalid/timeout needs the Profile author. |
| `profile-skill-stale`, missing installed skill from a package shipping one | Run `get` to install the locked skill; never edit installed copies. |

IDs above have the `wayfinder/` prefix. A Profile with no skill contributes rules
but no judgment. See [operations](../use-wayfinder/references/operations.md) for
troubleshooting. Profile/release changes are migration: do them only when asked,
using its changelog/guidance. `upgrade` intentionally advances mutable refs.

## Route by operation

Read the routed material before making the write. One write often touches
several rows.

| Doing | Read first |
| --- | --- |
| Creating or editing a concept: frontmatter, sources, links | [references/okf-authoring.md](./references/okf-authoring.md), then each Profile skill's routing |
| Creating a directory, placing, naming, moving, deprecating, deleting, mirroring | each Profile skill's routing |
| Creating or regenerating an `index.md` | [references/okf-authoring.md](./references/okf-authoring.md#files), then each Profile skill's routing |
| Profile Review, after any write or when asked | [references/profile-assessment.md](./references/profile-assessment.md) |
| Seeding a new bundle | the [`adopt-knowledge-bundle` skill](../adopt-knowledge-bundle/SKILL.md) |
| Preparing a reusable bundle for installation | [references/bundle-distribution.md](./references/bundle-distribution.md) |
| Anything no Profile skill covers | [references/OKF-0.2.md](./references/OKF-0.2.md) |

## The atomic bundle write

A write is complete only when all of these exist:

1. The concept file, following OKF and every Profile skill in the chain.
2. Every affected `index.md`. If a Profile in the chain requires generated
   indexes, run `wayfinder validate <bundle> --fix`. It writes them, then
   validates. Never edit a generated index by hand. Without such a Profile,
   `--fix` writes nothing and reports `wayfinder/fix-not-applied`. Update
   each `index.md` the bundle keeps yourself, per OKF §8. A fix that writes
   leaves okf's lock file, `.okf.lock`, at the bundle root; never commit it,
   and add it to the project's `.gitignore` if it is missing.
3. A `log.md` entry for a lifecycle event, under today's `## YYYY-MM-DD`
   heading, newest first, as `* **<Lead word>**: <what changed>`. The Profile
   skills say which events to log. A formatting-only change needs no entry.
4. A passing `wayfinder validate <bundle>` over the whole bundle. Repair
   deterministic failures before finishing.
5. A scoped Profile Review per
   [references/profile-assessment.md](./references/profile-assessment.md),
   with its report in the interaction or pull request.

If your host offers write tools built on Wayfinder's authoring library
(`KnowledgeWriter` in `package:wayfinder/authoring.dart`), such as create,
update, link and deprecate, prefer them to editing files. One call does steps
1 to 3 as one write: it writes the concept, rewrites only the generated
indexes the change affects, and records the log entry you pass exactly as
given. It judges the result before writing and refuses a write that adds an
error, naming the finding; repair what it names rather than editing around
it. It does not refuse an error the bundle already had, or a bundle no
Profile judged, so step 4 still applies: run `wayfinder validate <bundle>`,
or confirm the tool reports the candidate's gate as `PASS`. You still choose
the content and the log entry from each Profile skill, and you still run the
Profile Review in step 5.

## Where the Profile skills are silent

Follow [pinned OKF 0.2](./references/OKF-0.2.md). Silence is neither prohibition
of its mechanisms nor permission to invent conventions. Useful lookups: Attested
Computation (§10), source usage/lineage (§5.1), body headings (§4.2), canonical
`resource` (§§4.1/6.2), tag views (§3.1) and v0.1 fallbacks (§13).
