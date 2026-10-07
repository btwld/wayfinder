---
name: adopt-knowledge-bundle
description: Initialize the knowledge bundle in this repository. Bind it to a Profile in wayfinder.json, install that Profile's skill with wayfinder get, seed the root files under knowledge/, and write the AGENTS.md blocks that point agents into the bundle. Run once per repository.
disable-model-invocation: true
---

# Adopt Knowledge Bundle

Set up a repository to carry durable project knowledge as an OKF bundle at
`knowledge/`, bound to a Profile. This skill seeds the bundle and points
agents at it. The `author-knowledge-bundle` skill governs every later write.

The Profile decides the seed. Its skill, which `wayfinder get` installs,
carries the root-file templates and any lines the agent instructions need.
This skill runs the generic steps around them.

Inspect existing state, prepare what is missing, and apply changes within the
user's request. Ask only about unresolved choices, conflicting existing
instructions, or work outside the requested scope.

## Process

### 1. Explore

- `knowledge/` and project-root `wayfinder.json`. Does a bundle already
  exist? If so, run `wayfinder validate knowledge --output json` and report
  `profile.chain` or the diagnostic that replaces it. An existing bundle needs
  no seeding. Changing its Profile or release is migration work, not adoption.
- `AGENTS.md` at the repository root. Does it already have a
  `### Knowledge bundle` or `### Wayfinder` block? A `## Documentation`
  section left by an earlier adoption repeats the bundle block; fold it into
  that block.
- `CLAUDE.md` at the repository root. Does it import `AGENTS.md` with a line
  containing `@AGENTS.md`?

### 2. Choose the Profile

The user names the Profile: its id and its Git source (`git`, `ref`, and
`path`). Ask when they have not. Never pick one on their behalf.

### 3. Bind and install

Write project-root `wayfinder.json` from
[SEEDING.md](./SEEDING.md#wayfinderjson) with that source, then run
`wayfinder get`. It writes `wayfinder.lock` and installs the Profile's skill
at `.claude/skills/<id>/` and `.agents/skills/<id>/`. Include all three in the
change. If `get` cannot resolve the source, stop and report that the Profile
cannot be assessed yet.

### 4. Seed the bundle

Read the installed Profile skill and follow its adoption guidance. It gives
the `wayfinder.json` entry details, the root files, and the first log entry.
If the Profile ships no skill, or its skill has no adoption guidance, use the
OKF root files in [SEEDING.md](./SEEDING.md#okf-root-files). When the chain
has several Profiles, the root Profile's seed comes first and each child's
additions follow.

Seed only what the Profile's adoption guidance names. Without that guidance,
seed only the OKF root files. A `knowledge/` that holds only its root files
is fully set up.

Do not invent project types, tags, relationship names, or actor IDs while
seeding.

### 5. Point agents at it

Agent instructions live in `AGENTS.md`, and `CLAUDE.md` imports them with an
`@AGENTS.md` line. Add the blocks from
[SEEDING.md](./SEEDING.md#agent-instructions), with any lines the Profile's
adoption guidance adds, or update them in place if they exist. Do not append
duplicates or overwrite user edits to surrounding sections. The blocks belong
under an `## Agent skills` heading; create it if no other skill has, and
leave its other sub-blocks alone.

Then run `wayfinder setup --hooks` in the project root and commit the files
it writes (`.mcp.json`, `.githooks/`). Skip it, and say so, if
`wayfinder setup --help` does not list `--hooks`.

If an existing documentation tree remains, state which home is authoritative
for which material. Do not claim that old documents were migrated by seeding
a new bundle.

### 6. Validate and review

Run `wayfinder validate knowledge`. For a bundle that holds concepts under a
Profile that requires generated indexes, run
`wayfinder validate knowledge --fix` first. Then follow the authoring skill's
[Profile assessment reference](../author-knowledge-bundle/references/profile-assessment.md)
with **Scope: whole bundle**, including the Profile Review Report. Repair
clear defects in the new seed. For an existing bundle, report unrelated
defects without broadening setup into a migration.

### 7. Report the result

Tell the user what was seeded or preserved and where it starts
(`knowledge/index.md`, the binding in `wayfinder.json`, the installed
Profile skill), that `author-knowledge-bundle` governs every later write, and
that the tree grows out of what the project learns. Include the assessment
result. If a required check is unavailable or fails, state what remains
before adoption is complete. For a CI gate, point at
`wayfinder validate knowledge` and the Wayfinder README.
