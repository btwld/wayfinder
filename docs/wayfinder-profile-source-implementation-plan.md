---
kind: plan
date: 2026-09-28
repository: btwld/wayfinder
branch: split/profile-base
commit: ac302e31b24924ee4656797e7d2239d93b8d4211
worktree: /Users/leofarias/Documents/Codex/2026-09-28/can-you-find-the-wayfinder-pr/adr-pr-split
skill: engineering-kit:writing-plans
session: null
status: draft
---

# Implement Profile sources, lock resolution, and commands

This is the execution plan for the design in
[`wayfinder-profile-source-plan.md`](wayfinder-profile-source-plan.md). It is
intended for an agent working in the existing `adr-pr-split` checkout. The
implementation must preserve the current installed-Profile path while adding
the direct Git source model.

## Guardrails

These rules are part of the implementation contract. If a proposed change
would violate one, stop and resolve it against the design document before
editing code.

- Keep the new configuration shape direct: the profile map key is the Profile
  identity, with `source` and `applies_to` on that entry. Do not add a
  `knowledge_profile` alias, a separate `bundles` indirection, or a new
  `default_bundle` mechanism to the target syntax.
- Keep `applies_to` independent of `extends`. A Profile may apply directly to
  one or more bundle directories; inheritance is optional.
- Accept `source.ref` as an unprefixed branch, tag, or commit. Do not invent
  `branch/`, `tag/`, or `commit/` prefixes.
- Treat the fetched Profile manifest as authoritative for Profile identity and
  release. Do not repeat a Profile release in project configuration and do not
  execute arbitrary rules from fetched JSON.
- Keep `extends` additive and explicit. Support declared vocabulary or metadata
  additions only; reject arbitrary rule overrides, cycles, missing parents, and
  ambiguous composition.
- Hash canonical `wayfinder.json`, preserving array order and sorting object
  keys. Formatting-only changes must keep the lock current; semantic changes
  must make it stale.
- Keep `wayfinder.lock` limited to resolution metadata: lock version,
  configuration hash, source, requested ref, resolved commit, Profile path, and
  Profile release. Never write knowledge, credentials, Profile rules, or
  executable code into it.
- `get` resolves the declared refs and respects a current lock. `upgrade` is
  the only command that deliberately advances a mutable branch or tag. A
  current lock lets bundle commands reuse a current cache without network work.
- `validate`, `index`, `search`, and `graph` run the shared resolver before
  their normal operation when a project configuration is present. A missing
  or stale lock performs the equivalent of `get`; it does not silently upgrade.
- Preserve the legacy installed-Profile configuration and in-bundle 2026.2
  behavior until migration is explicitly implemented. Do not change the
  supported Profile release or OKF/Profile rules in this work.
- Keep the work within the two existing PRs. Do not create a new Profile
  namespace of commands, a `profile check` command, remote rule execution,
  nested bundle discovery, or client data fixtures.

## Dependencies and verified touchpoints

Implementation order matters because the CLI depends on the configuration and
resolution contracts.

- `packages/wayfinder/lib/src/wayfinder_config.dart` currently parses the
  legacy `profiles` plus `bundles` shape and resolves a selected bundle.
- `packages/wayfinder/lib/src/validation.dart` currently discovers and parses
  project configuration inside `ProfileValidator`.
- `packages/wayfinder_cli/lib/src/cli.dart` owns root command parsing and the
  `validate`, `index`, `search`, and `graph` dispatch paths.
- `packages/wayfinder_cli/lib/src/knowledge.dart` exposes
  `WayfinderKnowledge.defaultDataDirectory()` for local application data and
  cache placement.
- `docs/schemas/wayfinder.schema.json` currently describes the legacy shape and
  needs a compatibility-aware direct-shape update.
- `packages/wayfinder/test/configured_profile_test.dart` covers current
  configuration parsing and configured validation.
- `packages/wayfinder_cli/test/cli_test.dart` covers command help, argument
  errors, and command dispatch.
- The already updated guide and design plan are
  `docs/wayfinder-configuration.md`,
  `docs/wayfinder-profile-guide.html`, and
  `docs/wayfinder-profile-source-plan.md`.

## Task 1: Extend the configuration model without breaking legacy projects

**Files or components:**

- `packages/wayfinder/lib/src/wayfinder_config.dart`
- `docs/schemas/wayfinder.schema.json`
- `packages/wayfinder/test/configured_profile_test.dart`
- New focused parser tests beside the existing configuration tests if needed.

**Change:**

Add a direct Profile entry model with:

```text
profiles.<profile_id>.source.git
profiles.<profile_id>.source.ref
profiles.<profile_id>.source.path
profiles.<profile_id>.applies_to[]
profiles.<profile_id>.extends? 
profiles.<profile_id>.types/tags/actors?
```

Normalize `./knowledge` and reject absolute paths, parent traversal,
backslashes, `.`/`..`, duplicate applications, and overlapping bundle paths.
Keep project-root and symlink escape checks. A path may belong to one Profile
entry only. Preserve the existing parser as a compatibility branch for the
legacy shape, and make the direct shape the documented preferred form.

Validate source objects strictly. The first implementation supports Git
sources; reject unknown source kinds with a useful configuration error. Keep
Profile identity and release checks separate: identity comes from the map key
and fetched manifest, while the lock records the manifest release.

Parse `extends` as an optional Profile key. Resolve parent references after all
entries are parsed, reject missing parents and cycles, and allow only the
planned additive vocabulary/metadata merge. Do not add a general override
language.

Update the JSON Schema to describe both the legacy compatibility shape and the
new direct shape without accepting an object that mixes the two models.

**Validation:**

- Existing configured Profile tests remain green unchanged.
- Add direct-shape tests for one path, multiple paths, `./` normalization,
  duplicate/overlapping paths, unsafe paths, unknown Profile IDs, and manifest
  identity mismatch.
- Add tests for direct Profiles with and without `extends`, missing parents,
  cycles, and rejected override fields.
- Parse the updated schema and validate both representative legacy and direct
  documents.

## Task 2: Add canonical configuration hashing and lockfile types

**Files or components:**

- New core resolution/lock implementation under
  `packages/wayfinder/lib/src/`.
- `packages/wayfinder/lib/wayfinder.dart` exports if the CLI needs the types.
- Core package dependencies only when required by the chosen implementation.
- Focused lock/hash tests under `packages/wayfinder/test/`.

**Change:**

Implement one canonical JSON encoder for configuration hashing: sort object
keys recursively, preserve array order, emit stable JSON, and hash UTF-8 bytes
with SHA-256. The hash input is the semantic `wayfinder.json` object, not its
formatting or a re-serialized lockfile.

Implement strict read/write models for this shape:

```json
{
  "lock_version": 1,
  "configuration_sha256": "<canonical hash>",
  "profiles": {
    "bitwild_profile": {
      "source": "https://github.com/btwld/wayfinder",
      "requested_ref": "v2026.3",
      "resolved_commit": "<commit>",
      "path": "profile",
      "profile_release": "2026.3"
    }
  }
}
```

Write locks atomically through a temporary file in the same directory and a
rename. A failed fetch, manifest check, or serialization must leave the
previous lock untouched. Reject malformed locks, unsupported lock versions,
unknown Profile entries, and configuration hash mismatches as stale state.

**Validation:**

- Formatting-only configuration changes retain the same hash.
- Object-key or semantic changes invalidate the lock.
- Arrays remain order-sensitive.
- Malformed locks are reported as stale rather than treated as valid.
- Failed writes preserve the previous lock.
- Lock serialization never contains rules, credentials, or bundle content.

## Task 3: Implement Git source resolution and local cache reuse

**Files or components:**

- New resolver/cache implementation under `packages/wayfinder/lib/src/`
  or the CLI package if process and data-directory concerns require it.
- `packages/wayfinder_cli/lib/src/knowledge.dart` integration for the existing
  Wayfinder data directory.
- Resolver tests with temporary Git repositories under package tests.

**Change:**

Build a resolver that accepts the parsed direct configuration, lock state, and
an injectable cache/data directory. Resolve each Git source to an immutable
commit, read the Profile manifest under `source.path`, and verify its identity
against the Profile map key and its release against the supported validator.

Use a deterministic cache key derived from the repository URL and resolved
commit. Reuse a current lock and cache without network access. If the lock is
missing or its configuration hash is stale, resolve the requested ref and
write a new lock. `get` may move to the revision currently named by the
requested ref; `upgrade` explicitly refreshes mutable branch/tag refs before
writing a new lock. A commit ref resolves to that commit and never advances.

Keep all Git/process failures actionable: include the source and ref, preserve
the previous lock, and stop before bundle work. Do not place credentials in
arguments, lockfiles, logs, or fixtures. Do not load remote rule code; the
resolved manifest is metadata and the existing compiled Profile validator
remains authoritative.

**Validation:**

- Resolve a local temporary Git repository by tag, branch, and commit.
- Verify the selected subdirectory and manifest identity.
- Reuse a current lock without invoking network/fetch work.
- Refresh a stale lock after a semantic configuration change.
- Advance a mutable ref only through `upgrade`.
- Fail safely on missing path, bad manifest, missing ref, unreachable source,
  and interrupted writes.

## Task 4: Add `get` and `upgrade` with a shared resolver entry point

**Files or components:**

- `packages/wayfinder_cli/lib/src/cli.dart`
- New CLI resolver/service adapter if needed.
- `packages/wayfinder_cli/test/cli_test.dart`
- New command-focused tests for text and JSON diagnostics.

**Change:**

Add only these root commands:

```text
wayfinder get [project]
wayfinder upgrade [project]
```

The project argument defaults to the current directory and identifies the
project containing `wayfinder.json`. Keep the command surface flat; do not add
Profile-specific subcommands. Give both commands stable text output and an
optional JSON output mode if the existing CLI conventions support it.

`get` resolves declared sources and writes or refreshes the lock while
respecting a current lock. `upgrade` forces the deliberate mutable-ref update.
Neither command edits `wayfinder.json`.

Expose one shared resolver call that the other bundle commands can invoke. The
resolver must be safe to call more than once in one process and must return the
resolved project/profile context without reopening the knowledge index.

**Validation:**

- Root help lists `get` and `upgrade` and no new Profile namespace.
- Help and invalid-argument behavior do not open the retrieval/index model.
- Text and JSON output identify resolved/reused/upgraded state.
- Missing project config, malformed config, stale lock, and fetch failure have
  nonzero, actionable results.

## Task 5: Route bundle commands through resolution

**Files or components:**

- `packages/wayfinder_cli/lib/src/cli.dart`
- `packages/wayfinder/lib/src/validation.dart`
- Any shared command context introduced by Tasks 2–4.
- CLI tests and configured validation tests.

**Change:**

Before normal work, route `validate`, `index`, `search`, and `graph` through the
same resolver. Discover `wayfinder.json` using the existing bundle/project
path behavior; preserve the explicit validation config override where it
already exists. If no project configuration is present, preserve legacy
in-bundle behavior.

When the lock is missing or stale, perform the equivalent of `get` and write
the lock before reading bundle content. When current, resolution is a no-op.
A resolver failure stops the command before validation, indexing, search, or
graph work. Detached indexing must resolve before spawning its background
process.

Keep the current compiled Profile rules and independent OKF result behavior.
The resolver supplies source/manifest provenance; it does not silently change
validation severity or introduce remote execution.

**Validation:**

- Each command resolves a missing lock exactly once before its normal work.
- Current locks avoid network/fetch work.
- Stale locks refresh before bundle reads.
- Resolver failures do not create partial indexes or graph/search output.
- Legacy bundles and configured installed Profiles retain existing results.
- Detached index follows the same resolution behavior as foreground index.

## Task 6: Align documentation, fixtures, and migration evidence

**Files or components:**

- `docs/wayfinder-configuration.md`
- `docs/wayfinder-profile-guide.html`
- `docs/wayfinder-profile-source-plan.md`
- `docs/wayfinder-profile-source-implementation-plan.md`
- `docs/schemas/wayfinder.schema.json`
- Relevant test fixtures and package READMEs.

**Change:**

Keep the direct source example as the only main example. Label legacy syntax as
compatibility/migration material. Document the lock contents, canonical hash,
shared resolver behavior, and the distinction between `get` and `upgrade`.
Update any command help or README text that still presents the old schema as
the target model.

Do not add client knowledge or repository-specific project content to fixtures.
Use synthetic temporary Git repositories for resolver tests.

**Validation:**

- HTML parser succeeds.
- Every embedded JSON example parses.
- Markdown links resolve.
- The guide, design plan, implementation plan, schema, and CLI help use the
  same command/configuration vocabulary.

## Task 7: Run the full verification set and prepare review boundaries

**Files or components:** repository-wide.

**Change:**

Run formatting, static analysis, focused package tests, CLI tests, and the
repository contributor checks from `README.md`. Review the final diff for
legacy-model leakage, accidental Profile rule changes, credentials, client
data, and lockfile content beyond resolution metadata.

Keep implementation commits reviewable in dependency order: configuration
contract, lock/resolver, commands/integration, then documentation/tests. Keep
all work in the existing two-PR arrangement; do not open a third PR.

**Validation:**

- `dart format --output=none --set-exit-if-changed` on changed Dart files.
- `dart analyze` for affected packages.
- Focused `dart test` suites for core configuration/resolution and CLI commands.
- HTML/Markdown/schema checks from Task 6.
- `git diff --check`.
- Manual smoke test using a temporary Git Profile repository for `get`,
  `upgrade`, and `validate` with a current and stale lock.

## Handoff completion criteria

The implementation is ready for review only when all of these are true:

1. A direct `profiles.bitwild_profile` entry with Git `source` and
   `applies_to: ["./knowledge"]` resolves and validates.
2. Legacy installed-Profile projects continue to pass their existing tests.
3. A lock contains the canonical configuration hash and exact resolved commit.
4. `get` resolves/reuses sources; `upgrade` is the only deliberate mutable-ref
   advancement.
5. `validate`, `index`, `search`, and `graph` share the resolver behavior.
6. Missing/stale resolution failures preserve the old lock and prevent partial
   bundle work.
7. The guides and schema match the implemented syntax, and no new Profile
   rule or command namespace was introduced.
