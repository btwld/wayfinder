---
type: Decision
title: Judge the bundle against its own checkout
description: The gate binds the working tree's Profile packages, the lock and installed skills are not committed, and every link, anchor and rule help link must resolve.
status: stable
generated: { by: claude-code/fable-5, at: "2026-11-18T13:53:00Z" }
---

# Decision

## The gate binds the working tree's Profile packages

`python3 tool/ci/verify-knowledge.py` judges `knowledge/`. It commits the
working tree's Profile packages once to a temporary Git repository, copies
`wayfinder.json` and `knowledge/` beside it, points the copy's Profile source
at that commit, and runs `wayfinder get` and `wayfinder validate` there. The
packages are the ones the binding needs:
[`.wayfinder/profile`](../../.wayfinder/profile/wayfinder-profile.json) and its
parent, [`profiles/bitwild`](../../profiles/bitwild/README.md). The gate reads
uncommitted edits, so a rule change and the concept that satisfies it are
judged together in one pull request.

## The gate adds no rule and no verdict

The exit code is Wayfinder's: 0 for `PASS`, 1 for `FAIL`, and 2 for
`INCOMPLETE` or a run that could not start. Every rule is data in a Profile
package. With `--fix`, the gate copies the generated `index.md` files back
into `knowledge/` and writes nothing else.

## The lock and the installed skills are not committed

The root `wayfinder.json` names this repository at `"ref": "main"`.
`wayfinder.lock`, `.claude/skills/bitwild-profile/` and
`.agents/skills/bitwild-profile/` are ignored local state. A contributor who
runs `wayfinder get .` resolves the local `main` branch, which is enough for
`wayfinder query`, search and MCP. The gate never reads that lock.

## Every link, anchor and help link resolves

`python3 tool/ci/verify-links.py` reads the repository's tracked text and
applies four rules. It reads no frontmatter and knows no concept type.

- `link-resolves`: a relative Markdown link names an existing path.
- `anchor-names-a-heading`: a `#fragment` is a heading slug of its target.
- `self-url-resolves`: a `blob/main` URL of this repository names an existing
  path and heading.
- `rule-help-link-lands`: every rule id of a Profile package in this
  repository is a heading of the page its `docs` names.

The checker is permanent. It does not end with the migration into
`knowledge/`.

# Why

A binding cannot name the commit it ships in. `source.ref` takes a commit, a
branch or a tag
([`profile_resolver.dart`](../../packages/wayfinder/lib/src/project/profile_resolver.dart)),
and `wayfinder get` refuses `"ref": "HEAD"`. A committed lock is therefore
always one commit behind the packages beside it. A squash merge can orphan
the commit it pins. A pull request that bumps the package `format` cannot
pass, because the engine reads one format
([decision log](../../ARCHITECTURE.md#profile-owned-directory-policy-adr-0029))
and the lock still pins a package in the old one.

[`examples/README.md`](../../examples/README.md) states the same convention
for the example projects, whose Profile source is also this repository: "The
source checkout commits no lock, because the binding follows a branch."

This departs from what the documentation tells an adopter, which is to commit
the lock with `wayfinder.json`
([sources and lockfile](../../docs/wayfinder-configuration.md#sources-and-lockfile))
and to commit the installed skill directories
([Profile skills](../../docs/wayfinder-configuration.md#profile-skills)). An
adopter's lock pins a commit that already exists. Here the Profile source is
the commit under review. A committed skill would also be an older copy of
[`profiles/bitwild/skill/`](../../profiles/bitwild/skill/SKILL.md) beside the
original.

The cost is two ways to validate. Plain `wayfinder validate` reads the lock a
contributor resolved from local `main`, and the gate reads the working tree.
They differ only while a Profile package differs between `main` and the tree.

`wayfinder validate` reads no anchor and no link that leaves the bundle. This
repository keeps one source per fact by pointing at it, so a dead pointer
leaves a reader with nothing. The link checker covers what the engine has no
fact for.

# Rejected

- A committed lock pinned to an earlier commit of this repository, with the
  installed skills committed beside it. Every rule change needs two pull
  requests, a squash merge can orphan the pinned commit, a format bump
  deadlocks, and an older copy of the Bitwild skill sits beside the original.
- A project MCP configuration that runs the CLI from source. `dart run`
  writes build-hook text to stdout before the protocol starts, which breaks
  a stdio server.
- A pre-commit hook, a session hook or `wayfinder setup`. Each is a second
  place for the same two commands.
- Retiring the link checker when the migration ends. A URL that ships in a
  binary, a skill, a schema or a package cannot be repaired after release.
