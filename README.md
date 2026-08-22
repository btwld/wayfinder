# Concepta OKF

The home of the **Concepta OKF Profile** — a set of conventions for keeping durable project
knowledge as an [Open Knowledge Format][okf] bundle in the same repository as the code it
describes — together with the skills, tooling, and examples that put it to work in any
Concepta repository.

The profile is a *profile*, not a format. It defines no file type, no frontmatter field, and
no metadata semantics of its own; every mechanism it uses is defined by OKF and used with its
OKF meaning. OKF is authoritative — where the two appear to differ, OKF wins and the profile
is in error.

Current release: **2026.1**, profiling **OKF 0.2**. Status: Proposed. Its
immutable text is
[`profile/versions/okf-profile-2026.1.md`](profile/versions/okf-profile-2026.1.md).

The canonical profile and implementation guide currently hold the **unpublished
2026.2 integration draft** for issues #22 through #25. They are not a
distribution surface and MUST NOT be presented as the current release until
issue #19 verifies and publishes the complete release atomically. Changes to
skills, seeding material, examples, and compatibility evidence on the stacked
integration branches remain unpublished draft material until that gate passes;
the legacy verifier remains deprecated and is removed only when its replacement
assumes the CI gate.

[okf]: https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing

## The dividing line

Everything in this repository is **company-generic**: it holds *how Concepta works*.

A project's `knowledge/` bundle holds *what we know about that project* — its domain, its
decisions, its open questions. Nothing here is ever a prerequisite for reading one. A bundle
must stay readable on its own when a client receives only their project repository, so the
profile is referenced by version, never copied in.

That is why this repository is consumed rather than vendored: install the skills once, point
CI at the verifier, and let each project repository carry only its own knowledge.

## What is in here

| Path | Holds |
| --- | --- |
| [`profile/`](profile/) | The normative profile text — the standard itself |
| [`implementation/`](implementation/) | The companion implementation guide: adoption, index generation, validation, migration, distribution |
| [`skills/`](skills/) | The agent skills — the profile skill plus the engineering skills that write into a bundle |
| [`tools/`](tools/) | Repo-side tooling: the bundle verifier |
| [`examples/`](examples/) | A complete worked bundle you can read end to end |
| [`docs/ways-of-working.md`](docs/ways-of-working.md) | The shared engineering process, canonical here |

`profile/okf-profile.md` is the canonical release-integration path; its version
and publication status are declared at the top, never in the filename. During a
release integration it may therefore contain an explicitly unpublished draft
while the current release remains immutable under `profile/versions/`. When the
integration is published, the canonical path again names the current release.
That applies the profile's own §8.1 rule — version and status are metadata and do
not belong in an identity — without silently replacing an identified release.

## Getting started

### 1. Install the skills

The skills live in [`skills/`](skills/). Install them wherever your agent reads skills from —
for Claude Code that is `~/.claude/skills/`, either by copying the directories or by
symlinking them so updates here reach you with a `git pull`:

```bash
git clone git@github.com:btwld/okf-profile.git ~/lab/concepta-okf
for s in ~/lab/concepta-okf/skills/okf-profile ~/lab/concepta-okf/skills/engineering/*/; do
  ln -s "$s" ~/.claude/skills/"$(basename "$s")"
done
```

Symlinking is the better default — the skills are versioned with the profile they describe,
and a copy silently ages past it. See [skills/README.md](skills/README.md) for the full set
and what each one does.

### 2. Set up a project repository

In the repository you want to adopt the profile, run:

```
/setup-repo
```

It is prompt-driven, not a script: it explores what the repository already has, shows you what
it proposes, and writes only after you confirm. It configures three things —

- **Issue tracker** — where issues live, so the engineering skills know whether to call `gh`,
  write markdown under `.scratch/`, or follow a workflow you describe
- **Triage labels** — the label vocabulary, if the `triage` skill is installed
- **Knowledge bundle** — seeds the five root files of `knowledge/`, and writes the `AGENTS.md`
  blocks that point agents into it

**It creates no directories under `knowledge/`, and that is correct.** A directory
names a *subject*, and generic setup has no corpus from which to judge one (profile
§3.1). A repository whose `knowledge/` is only its root files is fully set up, not
half-finished — the tree grows out of what the project actually learns rather than
a guess made on day one. A genuine subject area may be small; no numeric threshold
decides it.

### 3. Work the flow

Once a repository is set up, the engineering skills read from the bundle and write back into
it:

| Skill | Invocation | What it does |
| --- | --- | --- |
| `okf-profile` | model-invoked | The profile as a skill. Any agent about to create, edit, deprecate, or move a file under `knowledge/` reaches it automatically |
| `domain-modeling` | model-invoked | Pins down terminology and records decisions — one Glossary Definition per term, ADRs into `architecture/`, durable non-architectural decisions as `Decision` concepts |
| `to-spec` | user-invoked | Turns a shaped problem into a specification, linked back to the concept it realizes |
| `to-tickets` | user-invoked | Slices a spec into tickets, linked to the concept that motivated them |
| `implement` | user-invoked | Reads the constraining concepts before coding, and links the work back with `Implemented by` |

You never invoke `okf-profile` yourself. It is model-invoked precisely because
structure an agent cannot see is structure an agent invents: a subject-named tree is not
self-inferrable, so an agent that skips the profile will confidently create `decisions/`.

### 4. Verify

```bash
python3 tools/verify_knowledge_bundle.py [--strict] [<repo-root>]
```

The verifier walks up for `knowledge/index.md`, so it runs against any repository from
anywhere inside it. It keeps the profile's two severities distinct (profile §14.1):

- An **OKF §11 violation** is a hard failure — the document cannot be interpreted, so it
  cannot be accepted. Exits nonzero.
- A **profile deviation** is an advisory finding — reported and attributed, never a reason to
  reject a bundle that is valid OKF. This deprecated verifier's `--strict` mode promotes
  legacy deviations, except the two advisories Profile 2026.2 explicitly keeps
  gate-neutral: unresolved internal edges and nonstandard relationship labels.

That asymmetry is deliberate. A profile that could reject valid OKF would have made itself a
competing standard, which the profile's §1.2 forbids.

## Examples

[`examples/knowledge/`](examples/knowledge/) is a complete bundle, small enough to read in one
sitting, showing the profile's central separations: a source event produces durable knowledge,
which links to an execution record, with generated indexes and an authored log.

It includes a two-concept subject area to show that truthful placement, not a
numeric threshold, determines structure.

## Reading order

- Adopting the profile in a project → [Getting started](#getting-started), then [`implementation/`](implementation/) §2
- Writing or editing a concept → the `okf-profile` skill; it delegates to
  [`profile/`](profile/) and carries the pinned OKF 0.2 text alongside it
- Building tooling → [`implementation/`](implementation/) §3 (index generation) and §4 (validation)
- Converting an existing `docs/` tree → [`implementation/`](implementation/) §5 (migration)
- Proposing a change to the profile → [Contributing](#contributing) below

## Contributing

Profile releases are driven by evidence, not by preference. A convention earns its way in by
being needed on a real corpus and by being *generic* — if it names a client, a domain, or a
project's own vocabulary, it belongs in that project's bundle, not here.

The loop:

1. Use the profile on a real project.
2. Open an issue for what it revealed — the case that broke, the rule that had to be decided
   locally, the convention two projects invented separately.
3. Where that justifies a convention, propose it against `profile/`, with its own row in the
   change record (profile §15.3) stating the **driver** and the migration impact.

The driver is the part that does the work. A change record row without one is a preference
wearing a rule's clothes, and the profile has no way to tell them apart later.

Two rules govern the edit itself. **Silence is deference**: where the profile says nothing and
OKF settles the point, follow OKF and do not mint a Concepta convention in its place — that is
the failure mode the profile is least able to detect, because a locally invented rule looks
like a convention rather than a divergence. And **precedence is a chain**: OKF wins over the
profile, which wins over the implementation guide.

## Profile or guide?

Two normative documents, and the difference is *what conforms to each*:

- The **profile** is normative on **bundles**. A bundle either conforms or it does not.
  "A project directory MUST name the subject its concepts genuinely share" belongs here.
- The **implementation guide** is normative on **implementations** — tools, adoptions,
  migrations. "A generator MUST be idempotent" constrains a program, never a bundle, which is
  why it could not have been written in the profile.

Both carry RFC 2119 force; neither is the soft one. The test for a new rule: does it describe
the bundle, or someone acting on the bundle?

## Still owed

Two pieces are specified and unimplemented:

- **The index generator** (guide §3). The profile defines deterministic semantic
  membership, grouping, ordering, labels, links, and descriptions. Until a
  generator exists, indexes are hand-maintained and validation catches drift
  (guide §3.4).
- **Stable finding IDs** (guide §4.2).
