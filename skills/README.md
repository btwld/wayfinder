# Skills

The agent skills for the [Concepta OKF Profile](../profile/concepta-okf-profile.md) (2026.1):
the profile itself as a skill, plus the engineering skills that read from and write into a
knowledge bundle.

## Installing

Install these wherever your agent reads skills from — for Claude Code, `~/.claude/skills/`.
Copy the directories or symlink them; symlinking is the better default, since the skills are
versioned with the profile they describe and a copy silently ages past it. See the
[root README](../README.md#1-install-the-skills) for a one-liner.

How you name and scope them locally is yours to decide. Nothing in the skills depends on the
install path, and nothing depends on a particular prefix.

## The set

| Skill | Invocation | What it does |
| --- | --- | --- |
| `concepta-okf-profile` | model-invoked | The profile as a skill: bundle structure and the area rules, the type vocabulary and the two registries, baseline frontmatter and the actor convention, path IDs and lifecycle, relationship labels, the index-and-log write, `references/` mirroring rules, and the execution-stays-external boundary. A closing `## Beyond this profile` section states that profile silence defers to OKF 0.2 rather than licensing a local convention, and names the families to look up. [SEEDING.md](concepta-okf-profile/SEEDING.md) holds the five root files for a new bundle; [OKF-0.2.md](concepta-okf-profile/OKF-0.2.md) is the pinned upstream spec. |
| `setup-repo` | user-invoked | Configures a repository for the other skills: issue tracker, triage labels, and the knowledge bundle. Seeds the five root files and creates **no** directories — a subject earns one only at three concepts, and even the profile-fixed names (`architecture/` and friends) are created lazily, on their first concept — so the tree cannot be laid out in advance. Writes the `AGENTS.md` blocks that point agents into the bundle and tell them to follow the profile skill before writing under `knowledge/`. |
| `domain-modeling` | model-invoked | Writes concepts: one Glossary Definition per term, ADRs into `architecture/`, and a Decision route for durable non-architectural decisions. Terms are filed with their subject, or at the bundle root until a subject earns an area. Bounded contexts are areas, so a word meaning two things needs no filename suffix — `ordering/order.md` and `billing/order.md`. Mechanics delegate to the profile skill. |
| `to-spec` | user-invoked | Turns a shaped problem into a specification. Discovery reads the area covering the subject, plus `architecture/` for system-wide structure; the published spec links back to the concept it realizes with `Specified by`. |
| `to-tickets` | user-invoked | Slices a spec into tickets, and links the breakdown to its motivating concept. A ticket chasing an open question takes `Tracked by`, not `Specified by`. |
| `implement` | user-invoked | Reads the constraining concepts before coding, and adds an `Implemented by` link when the work delivers a concept. |

Skills with no bundle awareness — interview techniques like `grilling`, and thin compositions
over them — need no changes to work alongside these, and none are shipped here.

## Why the profile is a skill

Structure and conventions an agent can't see are structure an agent invents. The profile skill
is **model-invoked** so any agent about to create, edit, deprecate, or move a file under
`knowledge/` reaches it without being asked — the mechanism that keeps written concepts
conforming instead of merely plausible.

It matters more under a subject-named tree than it would under a kind-named one. A kind-named
tree is self-documenting: an agent can infer that a Decision goes in `decisions/` without
reading anything. A subject-named tree cannot be inferred, so an agent that skips this skill
will invent a directory. The three-concept gate, the ban on kind-named directories, and "agents
file, humans create" only work if they are read.

It is also the single source of truth for concept mechanics: every other skill delegates
write mechanics to it. Where a skill restates structure so it can stand alone — the bundle
tree and frontmatter templates in `domain-modeling`, the boundary prose in `to-spec` and
`setup-repo`'s `AGENTS.md` template — the restatement must stay word-for-word true to the
profile, and those restatements are the first grep targets when a release changes a rule
(see below). That is what the implementation guide's §6 requires when it says
the profile skill must reach every environment that writes to a bundle — skill distribution is
what makes conformance *achievable* rather than merely checkable.

## Why OKF is a vendored file, not a second skill

The profile deliberately leaves parts of OKF undefined — Attested Computation, the source
credibility signals — and its silence is deference: an agent is required to *follow* OKF where
the profile says nothing, not merely to preserve valid OKF it doesn't recognize. Honouring that
needs the upstream text, so the text has to be reachable without a network fetch that fails in
headless or sandboxed runs.

[OKF-0.2.md](concepta-okf-profile/OKF-0.2.md) is that text: the spec verbatim (body verified
byte-identical to upstream), pinned at commit `3fcbb9f` under Apache-2.0 with attribution,
behind a `## Beyond this profile` pointer that names the families to look up. Pinning also fixes
a real drift bug — a `blob/main` URL silently becomes OKF 0.3 while the profile still claims to
bind to 0.2.

A file beats a second skill on invocation economics. A *user-invoked* OKF skill could not be
reached by the profile skill at all; a *model-invoked* one would pay permanent context load for
a description that fires rarely. A disclosed sibling file costs nothing until the pointer fires,
and nobody needs to invoke "the OKF spec" on its own — it is only ever reached from the profile.

## Keeping in step with the profile

A skill that restates a withdrawn rule is worse than a skill that says nothing: it produces
conforming files that teach the wrong thing, and no validator catches it. Two releases have
already changed skill text for exactly this reason.

**0.3.0** — a path freezes on citation *outside* the bundle, not at `status: stable`.
`concepta-okf-profile/SKILL.md` had carried "stable paths are immutable"; `SEEDING.md` had told
authors to move concepts "while they are still `draft`", which is the pressure the release
removed.

**2026.1** — `tags` carry topic only; an identifier other systems already cite is preserved
verbatim in the path; `Tracked by` joins the core labels; a `Specification` is separated from an
execution record by which system owns the artifact's state rather than by the word; and the
version format became `<year>.<serial>`. Five skills changed: `concepta-okf-profile`,
`setup-repo` (its `AGENTS.md` template carried the old specification sentence verbatim, so every
repository it seeded inherited the defect), `to-spec`, `to-tickets`, and `domain-modeling`.

When a profile rule changes, grep this tree for the old rule before shipping the release.

## Standing decisions

1. **`docs/agents/` stays outside the bundle.** Issue-tracker and triage-label files are
   operational agent configuration, not durable knowledge. Alternative considered and rejected
   for now: Guide concepts inside the bundle.
2. **Migration is not skill-resident.** These skills describe the target structure only;
   converting an existing `docs/` layout is a one-off task run against the profile skill and the
   generic method in [implementation guide §5](../implementation/concepta-okf-implementation-guide.md), not a permanent branch
   inside `setup-repo`.
