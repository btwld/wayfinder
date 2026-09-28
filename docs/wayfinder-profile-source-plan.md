# Wayfinder Profile source and lockfile plan

**Status: implemented on `split/profile-base`; pending review and merge.**

Implementation handoff: [guarded implementation plan](wayfinder-profile-source-implementation-plan.md).

## Goal

Let a project select a reusable Profile, say which bundle directories it applies to, and reproduce the resolved Profile source across machines and CI without repeating the Profile release in project configuration.

## Chosen shape

- A profile key is the Profile identity, such as `bitwild_profile`; no `knowledge_profile` alias is required.
- `source.git`, `source.ref`, and `source.path` locate a Profile package. `ref` accepts a branch, tag, or commit without prefixes.
- `applies_to` contains bundle paths relative to `wayfinder.json`; `./knowledge` is the documented form.
- `extends` is optional and names a parent Profile. It is independent of `applies_to`.
- The fetched manifest is authoritative for Profile release and must match the configured identity.
- The lockfile records the requested ref, resolved commit, internal path, manifest release, and canonical configuration hash.

## Commands

- `wayfinder get [project]` resolves declared sources and writes or refreshes `wayfinder.lock`, respecting a current lock.
- `wayfinder upgrade [project]` deliberately moves a branch or tag to its latest available revision.
- Every bundle command runs one shared resolver first. `wayfinder validate <bundle>` then checks configuration, lock, source cache, manifest identity, and every bundle file.

## Lock invariants

1. Hash canonical JSON, so formatting-only edits do not invalidate the lock.
2. A semantic `wayfinder.json` change makes the lock stale.
3. `get` may update the lock for the declared refs; `upgrade` is the explicit latest-version operation.
4. CI can require a current lock and a clean source cache after resolution.
5. The lockfile contains no rules, project vocabulary, knowledge, secrets, or executable validator code.

## Implementation sequence

### Configuration and source model

Update the schema and parser to support direct Profile entries, source kinds, `applies_to`, optional `extends`, and normalized safe bundle paths. Preserve the current installed-Profile path as a compatibility source.

**Validation:** parser tests for installed, Git, local, branch, tag, commit, direct application, extension, duplicate application, overlapping paths, and manifest mismatch.

### Lock resolution

Add canonical configuration hashing, lock read/write, Git resolution, cache layout, commit verification, and atomic lock replacement. Put the resolution step behind one shared resolver: `get` resolves declared refs, while `validate`, `index`, `search`, and `graph` invoke that resolver when the lock is missing or stale. A current lock is a no-op and can run from a current source cache without network access. Only `upgrade` deliberately advances a mutable branch or tag.

**Validation:** unchanged configuration reuses the lock; semantic configuration changes refresh it; formatting-only changes do not; missing or stale locks resolve before bundle work; failed resolution preserves the previous lock.

### Commands and diagnostics

Add `get` and `upgrade`; route every bundle command through the shared resolver, then run its normal operation. `get` writes or refreshes the lock for the declared refs. A bundle command that needs resolution performs the equivalent of `get` before checking its files. Add text and JSON diagnostics for resolution and automation.

**Validation:** command help, text/JSON diagnostics, current-lock offline checks, branch movement only through `upgrade`, and missing-cache recovery.

### Documentation and migration

Update the configuration guide and HTML guide with direct Git behavior and the retained installed-Profile compatibility path. Provide migration guidance from the legacy `profiles` plus `bundles` shape. Keep Profile rules and the validator contract unchanged.

**Validation:** Markdown links, HTML/JSON parsing, schema examples, and the existing Profile/CLI test suites.

## Non-goals

This plan does not add arbitrary Profile rule overrides, remote rule execution,
silent upgrades during validation, nested bundle discovery, or a third
configuration layer for `default_bundle`. Validation may resolve a missing or
stale lock through the shared resolver; only `upgrade` moves a current
branch or tag forward.
