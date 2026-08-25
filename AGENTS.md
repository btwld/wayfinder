# Agent instructions (repo)

You are working in the home of the **Concepta OKF Profile** — a standard, its implementation
specification, the skills that apply it, and the tooling that checks it. You are not working in
a project repository. Nothing here describes a client, a domain, or a product; everything here
describes *how Concepta works*.

Read [README.md](README.md) for the layout, then the part of the tree you are changing.

## Precedence is a chain

> **OKF** wins over the **profile**, which wins over the **specification**.

Every link is one-directional and none of them is negotiable.

- `profile/okf-profile.md` MUST NOT redefine, extend, or narrow any OKF field's
  meaning. Where it appears to, OKF governs and the profile is in error.
- `implementation/okf-implementation-guide.md` MUST NOT restate, extend, or narrow a
  profile rule. What it may do is bind behaviour the profile deliberately leaves open. It is
  normative on *implementations* — tools, adoptions, migrations — never on bundles.
- What real use revealed is never normative on its own. It justifies a release; it does not
  constitute one. A finding becomes a rule only by being written into `profile/` as one.

## Silence is deference

Where the profile says nothing and OKF settles the point, **follow OKF**. Do not mint a
Concepta convention in its place, and do not read profile silence as an invitation to invent
one.

This is the failure mode the profile is least able to detect, because a locally invented rule
looks like a convention rather than a divergence — and it is how a profile quietly becomes the
competing standard its §1.2 forbids. The pinned OKF 0.2 text is in the repository at
`skills/okf-profile/OKF-0.2.md`; consult it rather than guessing.

Silence is also not prohibition. Where OKF permits something and the profile says nothing, it
is permitted. The narrowings are the ones written as an explicit MUST or MUST NOT.

## Stay generic

A convention belongs here only if it is needed on a real corpus **and** holds for any project.
If a proposed rule names a client, a domain, a product, or a project's own vocabulary, it
belongs in that project's `knowledge/` bundle, not in this repository. Naming a project's
subjects is an explicit non-goal (profile §1.2).

The examples are the sharp edge of this. Every directory name in the profile outside the four
it fixes — `architecture/`, `ways-of-working/`, `interactions/`, `references/` — is
illustrative, and MUST read as one plausible project's name rather than a name another project
should adopt.

## Changing the profile

A convention change is not a text edit. It needs, in the same change:

1. The rule itself, written as an explicit MUST, MUST NOT, SHOULD, SHOULD NOT, or MAY.
2. A row in the change record (profile §15.3) naming the sections touched and the **driver** —
   what real use revealed the gap.
3. A migration sentence: whether an existing conformant bundle stays conformant, and what it
   must do if not. The version number does not carry this; the sentence does.
4. A new version, `<year>.<serial>`. Never semver — OKF uses semver, and the formats are kept
   distinct so a profile release can never be mistaken for an OKF one.

Superseded releases are snapshotted into `profile/versions/`. The canonical path never changes,
because version and status are metadata and do not belong in an identity (profile §8.1).

An upstream OKF release requires a new profile release **and** a compatibility review, even
when no Concepta convention otherwise changes. A release MUST NOT claim compatibility with an
OKF version it has not been reviewed against.

## Changing the skills

The skills are the distribution surface: they are what makes the profile reachable in a
repository that has never seen it. Two consequences:

- **A skill that restates a withdrawn rule is worse than a skill that says nothing.** It
  produces conforming files that teach the wrong thing, and no validator catches it. When a
  profile rule changes, grep the skills for the old rule before shipping.
- **Concept mechanics live in `okf-profile` and nowhere else.** Every other skill
  delegates to it. Do not restate bundle structure, frontmatter, or the type vocabulary in a
  second skill.

Consumers install these by copy or symlink into their own agent's skills directory. Assume
someone is running a copy from an older commit.

## Rules

- The issue is your task, the document you are changing is your context, the validation gate is
  your check.
- Propose a PR that references the issue and updates the affected document in the same change.
- Do not widen scope beyond the issue. If anything is unclear, ask rather than assume.
- This repository holds no client data and no project knowledge. Store nothing of a client's;
  read client data live and read-only via an MCP.

## Ways of working

The shared engineering process — intake, triage, spec, tickets, implement, review, done —
is canonical in the [concepta-engineering](https://github.com/conceptadev/concepta-engineering)
repository (`docs/ways-of-working.md` there), alongside the workflow skills that run it.
