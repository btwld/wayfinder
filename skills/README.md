# Skills

The agent skills for the [Concepta OKF Profile](../profile/okf-profile.md) (2026.2):
one action-named family, shipped as the `concepta-knowledge` plugin. Rule text lives
once, under `author-knowledge-bundle/references/`; the other skills are entry points
that read it by sibling path (ADR-0005).

## The family

| Skill | Invocation | What it does |
| --- | --- | --- |
| [`author-knowledge-bundle`](author-knowledge-bundle/) | model-invoked | Create, edit, move, deprecate, or mirror bundle content. A short routing `SKILL.md` — release dispatch, operation routing, the atomic bundle write — over `references/` split by operation, with the pinned OKF 0.2 spec vendored alongside. Owns Profile Review for both scopes via [references/profile-assessment.md](author-knowledge-bundle/references/profile-assessment.md). |
| [`adopt-knowledge-bundle`](adopt-knowledge-bundle/) | user-invoked | Initialize a repository: declare the release, seed the root files ([SEEDING.md](adopt-knowledge-bundle/SEEDING.md)), write the `AGENTS.md` blocks that point agents at `author-knowledge-bundle`. Creates **no** directories — generic setup has no corpus from which to judge a subject. |
| [`assess-knowledge-bundle`](assess-knowledge-bundle/) | user-invoked | Deliberate whole-bundle assessment: `okfp validate` plus every contextual judgment rule, emitting the standard Profile Review Report. An entry point into the shared assessment reference, not a second copy of it. |

There is no `migrate-knowledge-bundle` — migration stays a one-off task, not a resident
skill ([ADR-0005](../docs/adr/0005-skill-family-and-plugin-distribution.md)). The
engineering workflow skills — repo setup, domain modeling, spec, tickets,
implementation — live in
[concepta-engineering](https://github.com/conceptadev/concepta-engineering); they
delegate every bundle write here.

## Installing

See the [root README](../README.md#1-install-the-skills) for the commands. Install the
family as a unit — the skills reference each other by sibling path, so a partial
install breaks the routing.

## Why the profile is a skill

Structure and conventions an agent can't see are structure an agent invents.
`author-knowledge-bundle` is **model-invoked** so any agent about to create, edit,
deprecate, or move a file under `knowledge/`, or asked to review bundle changes,
reaches it without being asked — the mechanism that keeps written concepts conforming
and contextual assessment complete.

It matters more under a subject-named tree than it would under a kind-named one. A
kind-named tree is self-documenting: an agent can infer that a Decision goes in
`decisions/` without reading anything. A subject-named tree cannot be inferred, so an
agent that skips this skill will invent a directory. Subject-based placement and the
contextual prohibition on speculative structure only work if they are read.

It is also the single source of truth for concept mechanics: every other skill —
here and in concepta-engineering — delegates write mechanics to it. Where a skill
restates structure so it can stand alone — the boundary prose in
`adopt-knowledge-bundle`'s `AGENTS.md` template, the tree in
`references/structure-and-lifecycle.md` — the restatement must stay word-for-word
true to the profile, and those restatements are the first grep targets when a release
changes a rule (see below). That is what the implementation guide's §6 requires when
it says the profile skill must reach every environment that writes to a bundle —
skill distribution is what makes conformance *achievable* rather than merely
checkable.

## Why OKF is a vendored file, not a second skill

The profile deliberately leaves parts of OKF undefined — Attested Computation, the
source credibility signals — and its silence is deference: an agent is required to
*follow* OKF where the profile says nothing, not merely to preserve valid OKF it
doesn't recognize. Honouring that needs the upstream text, so the text has to be
reachable without a network fetch that fails in headless or sandboxed runs.

[author-knowledge-bundle/references/OKF-0.2.md](author-knowledge-bundle/references/OKF-0.2.md)
is that text: the spec verbatim (body verified byte-identical to upstream), pinned at
commit `3fcbb9f` under Apache-2.0 with attribution, behind a `## Beyond this profile`
pointer that names the families to look up. Pinning also fixes a real drift bug — a
`blob/main` URL silently becomes OKF 0.3 while the profile still claims to bind
to 0.2.

A file beats a second skill on invocation economics. A *user-invoked* OKF skill could
not be reached by `author-knowledge-bundle` at all; a *model-invoked* one would pay permanent
context load for a description that fires rarely. A disclosed sibling file costs
nothing until the pointer fires, and nobody needs to invoke "the OKF spec" on its
own — it is only ever reached from the profile.

## Keeping in step with the profile

A skill that restates a withdrawn rule is worse than a skill that says nothing: it
produces conforming files that teach the wrong thing, and no validator catches it.
Releases have already changed skill text for exactly this reason.

**0.3.0** — a path freezes on citation *outside* the bundle, not at `status: stable`.
The profile skill had carried "stable paths are immutable"; `SEEDING.md` had told
authors to move concepts "while they are still `draft`", which is the pressure the release
removed.

**2026.1** — `tags` carry topic only; an identifier other systems already cite is preserved
verbatim in the path; `Tracked by` joins the core labels; a `Specification` is separated from an
execution record by which system owns the artifact's state rather than by the word; and the
version format became `<year>.<serial>`. Five skills changed, including `setup-repo`, whose
`AGENTS.md` template carried the old specification sentence verbatim — so every
repository it seeded inherited the defect.

**2026.2** — relationships remain ordinary untyped OKF edges,
including unresolved targets; external citations freeze a path only when they cannot
be repaired; stable concepts normally deprecate; and mirroring requires a cited
source at genuine availability risk whose material is suitable for repository
visibility. `author-knowledge-bundle` carries these authoring and
Profile Review boundaries while downstream engineering skills continue to delegate
the mechanics.

When a profile rule changes, grep this tree **and the concepta-engineering
repository** for the old rule before shipping the release.
