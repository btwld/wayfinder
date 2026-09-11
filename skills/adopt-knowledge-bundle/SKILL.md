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

This is a prompt-driven skill. Inspect existing state, prepare the missing
setup, and apply changes within the user's request. Preserve prior authorization;
ask only about unresolved choices, conflicting existing instructions, or work
outside the requested scope.

## Process

### 1. Explore

- `knowledge/` — does the bundle exist? If so, read `knowledge/profile.md` and
  report the declared `concepta_profile` and `okf_version`; an existing bundle
  needs no seeding, and changing its declared release is a migration, not
  adoption.
- `AGENTS.md` at the repo root — does it exist? Does it already have a
  `### Knowledge bundle` or `### Wayfinder` block? A `## Documentation` section
  left by an earlier adoption repeats the bundle block; fold it into that block.
- `CLAUDE.md` at the repo root — does it exist? Does it import `AGENTS.md`
  (a line containing `@AGENTS.md`)?

### 2. Prepare the changes

The Concepta OKF Profile fixes the bundle's configuration, so there is nothing
to ask about its shape. Prepare only the missing or requested changes:

- The bundle's root files, when they need seeding
- The `### Knowledge bundle` and `### Wayfinder` blocks for `AGENTS.md`
- The files `wayfinder setup --hooks` writes, if the project lacks them
- The `@AGENTS.md` line for `CLAUDE.md`, if it isn't already there

If the user requested a proposal or review before writing, present that draft and
wait. Otherwise complete the authorized setup. Preserve existing bundle content
and unrelated agent instructions.

### 3. Seed the bundle

When no bundle exists, follow [SEEDING.md](./SEEDING.md) exactly; it owns the
root-file contents and the conditions they implement. If a bundle already exists,
skip seeding. Repairing a partial bundle or changing its release is separate work;
report the gap and use the authoring or migration workflow when authorized.

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
its other sub-blocks (issue tracker, triage labels) alone — they are another
tool's concern, out of this skill's scope.

```markdown
### Knowledge bundle

Durable project documentation and knowledge live in the OKF bundle at
`knowledge/`, following the Concepta OKF Profile (versions declared in
`knowledge/profile.md`). Start at `knowledge/index.md`, then the area index,
then the concept.

Follow the `author-knowledge-bundle` skill before writing anything under
`knowledge/` — including before creating a directory there. Execution records
stay in the tracker and are linked from concepts.

### Wayfinder

Search the bundle before answering questions about the project's decisions,
requirements, conventions, ownership or prior analysis. Use the `wayfinder` MCP
server's `search` tool, or `wayfinder search knowledge "<question>"` when MCP is
unavailable. Search never answers from a stale index: if it reports one, run
`index` and search again. Verify cited passages before relying on them, and run
`validate` before claiming the bundle conforms. The `use-wayfinder` skill has
the details.

Run `wayfinder setup --hooks` once per clone (Wayfinder 0.0.3 or later): it
registers the MCP server in `.mcp.json` and refreshes the index after agent
turns, pulls, checkouts and rebases.
```

Then run `wayfinder setup --hooks` in the project root and commit the files it
writes (`.mcp.json`, `.claude/settings.json`, `.codex/hooks.json`, `.githooks/`).
That flag shipped in 0.0.3; skip it and say so if `wayfinder setup --help` does
not list `--hooks`.

If an existing documentation tree remains, state which home is authoritative for
which material, as implementation guide §2.2 requires. Do not claim that old
documents were migrated by seeding a new bundle.

### 5. Validate and review

Read [the authoring skill](../author-knowledge-bundle/SKILL.md) and perform its
release dispatch. Follow its
[Profile assessment reference](../author-knowledge-bundle/references/profile-assessment.md)
with **Scope: whole bundle**, including automated validation and the Profile
Review Report. Repair clear defects in the new seed within the authorized scope.
For an existing bundle, report unrelated defects without silently broadening setup
into a migration or whole-bundle repair.

### 6. Report the result

Tell the user what was seeded or preserved and where it starts (`knowledge/index.md`,
versions in `knowledge/profile.md`), that `author-knowledge-bundle` governs
every later write, and that the tree grows out of what the project actually
learns — concepts land at the root first, and subject directories are earned,
never predicted. Include the assessment result; if a required check is unavailable
or fails, state what remains before adoption is complete. For the CI validation
gate (`wayfinder validate knowledge`), point at the Wayfinder repository's README
and implementation guide §2.
