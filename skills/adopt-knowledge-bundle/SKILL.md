---
name: adopt-knowledge-bundle
description: Initialize the knowledge bundle in this repository — seed the root files under knowledge/, declare the Concepta Profile release, and write the AGENTS.md blocks that point agents into the bundle. Run once per repository.
disable-model-invocation: true
---

# Adopt Knowledge Bundle

Set up a repository to carry durable project knowledge as an OKF bundle at
`knowledge/`, following the Concepta OKF Profile. This skill seeds the bundle
and points agents at it; all later writes are governed by the
`author-knowledge-bundle` skill.

This is a prompt-driven skill, not a deterministic script. Explore, present
what you found, confirm with the user, then write.

## Process

### 1. Explore

- `knowledge/` — does the bundle exist? If so, read `knowledge/profile.md` and
  report the declared `concepta_profile` and `okf_version`; an existing bundle
  needs no seeding, and changing its declared release is a migration, not
  adoption.
- `AGENTS.md` at the repo root — does it exist? Does it already have a
  `### Knowledge bundle` block or a `## Documentation` section?
- `CLAUDE.md` at the repo root — does it exist? Does it import `AGENTS.md`
  (a line containing `@AGENTS.md`)?

### 2. Confirm

The Concepta OKF Profile fixes the bundle's configuration, so there is nothing
to ask about its shape. Show the user a draft of:

- The bundle's root files, when they need seeding
- The `### Knowledge bundle` and `## Documentation` blocks for `AGENTS.md`
- The `@AGENTS.md` line for `CLAUDE.md`, if it isn't already there

Let them edit before writing.

### 3. Seed the bundle

Follow [SEEDING.md](./SEEDING.md) exactly; it owns the root-file contents and
the conditions they implement.

**Create no directories.** Canonical seeding creates only the bundle root; the
`author-knowledge-bundle` skill decides later structure from the project's
actual knowledge. A repository whose `knowledge/` is only its root files is
fully set up, not half-finished.

### 4. Point agents at it

Agent instructions live in **`AGENTS.md`**, with `CLAUDE.md` importing it via a
`@AGENTS.md` line. Add the blocks below, or update them in place if they
already exist — don't append duplicates, and don't overwrite user edits to
surrounding sections. The `### Knowledge bundle` block belongs under an
`## Agent skills` heading; create that heading if no other skill has, and leave
its other sub-blocks (issue tracker, triage labels) alone — the
`setup-repo` skill from the `concepta-engineering` plugin owns those.

```markdown
### Knowledge bundle

Durable project knowledge is an OKF bundle at `knowledge/`, following the
Concepta OKF Profile (versions declared in `knowledge/profile.md`). Start at
`knowledge/index.md`, then the area index, then the concept.

Follow the `author-knowledge-bundle` skill before writing anything under
`knowledge/` — including before creating a directory there.

## Documentation

Durable docs are OKF concepts in `knowledge/` — check `knowledge/index.md`
first to find the right concept, then open it directly. Execution records are
not knowledge: anything a tracker owns the state of — an issue, a ticket, a
pull request, including a spec opened as one — lives in the issue tracker and
is linked from concepts, never mirrored into the bundle.

"Specification" is a genre, not a location. A specification the project
maintains as durable knowledge, whose only state is `status`, is a
`Specification` concept filed with its subject. Every durable specification has
exactly one lifecycle owner; one artifact never lives in both places (profile
§5.2, §7.3).
```

### 5. Done

Tell the user the bundle is seeded and where it starts (`knowledge/index.md`,
versions in `knowledge/profile.md`), that `author-knowledge-bundle` governs
every later write, and that the tree grows out of what the project actually
learns — concepts land at the root first, and subject directories are earned,
never predicted. For the CI validation gate (`okfp validate knowledge`), point
at the okf-profile repository's README and implementation guide §2.
