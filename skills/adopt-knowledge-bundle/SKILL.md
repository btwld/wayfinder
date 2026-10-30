---
name: adopt-knowledge-bundle
description: Initialize the knowledge bundle in this repository. Bind it to a Profile in wayfinder.json, install that Profile's skill with wayfinder get, seed the root files under knowledge/, and write the AGENTS.md blocks that point agents into the bundle. Use for each new bundle.
disable-model-invocation: true
---

# Adopt Knowledge Bundle

Set up `knowledge/` (or the requested bundle path), bind it to the user's Profile
and route agents to it. The Profile's skill supplies seed conventions;
`author-knowledge-bundle` governs later writes.

Inspect existing state and apply authorized changes. Ask only about unresolved
choices, conflicting instructions or work outside scope. Hosts can use the
adoption library; [SEEDING.md](./SEEDING.md) documents its generic seed.

## 1. Explore

- Inspect the bundle and root `wayfinder.json`. Validate existing bundles with
  `wayfinder validate knowledge --output json`; report the chain or diagnostic.
  Preserve their content. Changing a Profile/release is migration, not adoption.
- Inspect `AGENTS.md` for `### Knowledge bundle`/`### Wayfinder`. Fold an older
  duplicated `## Documentation` block into the bundle block.
- Check whether root `CLAUDE.md` imports `@AGENTS.md`.

## 2. Choose the Profile

Use the user's Profile id and Git source (`git`, `ref`, `path`). Ask for missing
choices; never select a Profile on their behalf.

## 3. Bind and install

Create an empty bundle directory if missing (`get` requires it). Write the
binding from [SEEDING.md](./SEEDING.md#wayfinderjson), run `wayfinder get`, and
include the binding, lock and installed `.claude/skills/<id>/` and
`.agents/skills/<id>/` in the change. If resolution fails, report that the Profile
cannot yet be assessed. An unmarked skill directory belongs to someone else;
ask before moving it aside.

Add `knowledge/.okf.lock` to `.gitignore` unless already covered or the user
prefers committing it. okf leaves this file after writes.

## 4. Seed the bundle

Read installed Profile skills, root first, and follow their adoption guidance.
Seed only what they name. Without guidance, use only OKF's root `index.md` and
`log.md` from [SEEDING.md](./SEEDING.md#okf-root-files). Root files alone are a
complete setup. Never invent project types, tags, relationships or actor IDs.

## 5. Point agents at it

Add/update [the instruction blocks](./SEEDING.md#agent-instructions) under
`## Agent skills` in `AGENTS.md`, with the Profile's additions. Preserve user edits
and other blocks; avoid duplicates. `CLAUDE.md` imports `@AGENTS.md`.

Run `wayfinder setup --hooks` and include its `.mcp.json`/`.githooks/` changes.
If `setup --help` lacks `--hooks`, skip it and report that. If old docs remain,
state which home governs which material; seeding does not migrate them.

## 6. Validate and review

For concepts under generated-index rules, run `wayfinder validate knowledge --fix`;
then require a passing whole-bundle validation and the
[Profile assessment](../author-knowledge-bundle/references/profile-assessment.md)
with **Scope: whole bundle**. Repair clear seed defects; report unrelated existing
defects without expanding into migration.

## 7. Report

Name seeded/preserved files, binding and Profile skills, the assessment outcome
and any checks still needed. Point to `knowledge/index.md`,
`author-knowledge-bundle` for future writes and `wayfinder validate knowledge`
for CI. The tree grows from what the project learns.
