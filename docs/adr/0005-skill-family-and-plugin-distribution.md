# ADR-0005: Action-named skill family, plugin distribution, engineering extraction

- Status: accepted
- Date: 2026-08-25
- Issue: [#42](https://github.com/conceptadev/okf-profile/issues/42)
- Partially supersedes: [ADR-0004](0004-closed-concepta-profile-validator.md) — only its
  single-skill clause, as stated below; every other ADR-0004 decision stands.

## Context

With Profile 2026.2 and the closed validator shipped (ADR-0004, #37), the
architecture assessment turned to what this repository distributes and how.
Three findings drove this record.

First, the engineering workflow skills — `domain-modeling`, `to-spec`,
`to-tickets`, `implement`, and the issue-tracker and triage parts of
`setup-repo` — encode a particular way of developing software, not behavior
required to author or assess a Concepta-profiled bundle. They consume the
Profile skill by delegation; nothing in them is Profile mechanics. The same
holds for `docs/ways-of-working.md`, the process those skills implement.

Second, `okf-profile` names a standard, not an action. A skill name is a
context pointer: the caller should read what changes when it is invoked.

Third, the copy-or-symlink installation model makes cross-skill file
references fragile — a skill cannot rely on a sibling being present or
current. A survey of the ecosystem (anthropics/skills, obra/superpowers)
found plugin-marketplace distribution throughout: skills ship flat, as a
unit, defined by a `.claude-plugin/marketplace.json`, with no repository
generating packaged copies of shared text.

## Decision

**Repository scope.** This repository holds the standard, its skill family,
and its validator. The engineering workflow skills and
`docs/ways-of-working.md` move to their own repository
(`concepta-engineering`) with their own plugin definition. They keep
delegating bundle mechanics to the Profile skill by skill name, which is
install-location independent.

**Distribution unit.** The skill family ships as one plugin,
`concepta-knowledge`, defined by `.claude-plugin/marketplace.json` in this
repository. The plugin installs as a unit, so sibling-path references
between family skills are reliable. No packaged copies are generated from
shared sources: a generated copy is still a copy, and a copy silently ages.
Copy or symlink installation remains a documented fallback, with the caveat
that only whole-family installation keeps sibling references valid.

**Skill family.** Three action-named skills replace `okf-profile` and the
bundle-facing parts of `setup-repo`:

- `author-knowledge-bundle` (model-invoked) — create, edit, move, deprecate,
  or mirror bundle content; owns the atomic bundle write (concept + affected
  indexes + log entry + validation + scoped review) and all Profile rule
  text, held under `references/` behind a short routing `SKILL.md`.
- `adopt-knowledge-bundle` (user-invoked) — initialize a repository:
  declare the release, seed the root files, write the agent-instruction
  blocks that point agents at `author-knowledge-bundle`.
- `assess-knowledge-bundle` (user-invoked) — deliberate whole-bundle
  assessment: run `okfp validate`, apply the judgment rules from the shared
  assessment reference, emit the standard Profile Review Report.

Rule text lives once, under `author-knowledge-bundle/references/`; the other
skills read it by sibling path. `migrate-knowledge-bundle` stays deferred
until a real migration demonstrates the need — migration remains a one-off
task run against the guide's §5 method, not a resident skill.

This supersedes one ADR-0004 clause: "One model-invoked `okf-profile` skill
owns both the authoring and post-write Profile Review workflows." The split
follows the seam ADR-0004 itself drew — routine review of changed concepts
stays inside authoring; adoption, upgrades, migrations, and reorganizations
review the whole bundle — and turns that second mode into the user-invoked
entry point it already was in practice. Scoped review remains part of every
authoring write; no review obligation is weakened.

**Package placement.** The Dart package moves to `packages/okf_profile/`
under a pub workspace; the root `pubspec.yaml` becomes workspace
configuration only. This clears the validator's build files out of the
standard's root and follows the documented pub convention for repositories
whose package is not the repository's identity. The SDK floor rises to
3.6.0, which workspaces require.

**Considered and rejected: retitling the implementation guide.** The
assessment proposed "Implementation Specification". The guide's own 2026.2
change record documents the deliberate rename in the opposite direction — a
subordinate document called "the spec" inverted the precedence it exists to
state, and the canonical Profile text cites `okf-implementation-guide.md` by
name. The title stands.

**No Profile release.** No bundle rule changes. Skills are the distribution
surface, and guide §6 already delegates distribution mechanics to the
repository READMEs, so neither the Profile nor the guide text changes.

## Consequences

- Consumers reinstall: `/plugin install` replaces per-skill symlinks. Old
  `okf-profile` symlinks dangle after the rename and must be removed.
- Consumer repositories seeded by the old `setup-repo` carry an `AGENTS.md`
  block naming the `okf-profile` skill; it should be updated to
  `author-knowledge-bundle` on next contact. This is an instruction-text fix,
  not a Profile migration — bundles are unaffected.
- The engineering repository must update its delegation references from
  `okf-profile` to `author-knowledge-bundle`, and release-change greps now
  sweep two repositories.
- `skills/README.md` is rewritten around the family; the root `README.md`
  workflow-skill material becomes a pointer to `concepta-engineering`.
- The 2026.2 rule text is repartitioned, not changed; the restructuring diff
  must show relocation only.
- Standing decision "migration is not skill-resident" is unchanged and now
  recorded here rather than in `skills/README.md` prose.
