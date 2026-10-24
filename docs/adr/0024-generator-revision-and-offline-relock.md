# ADR-0024: Pin the generator revision, and relock offline

- Status: accepted
- Date: 2026-10-24
- Scope: what `matches-generated` `version` names, the project root a write binds within, and an offline relock of `wayfinder.json`; no Profile rule and no change to verdicts
- Amends: [ADR-0015](0015-profile-rule-catalogs.md), [ADR-0018](0018-embeddable-libraries.md) and [ADR-0020](0020-programmatic-adoption.md)
- Builds on [ADR-0019](0019-profile-aware-writes.md)

## Context

ADR-0015, ADR-0018 and ADR-0020 stay as they were accepted. This record
carries three decisions that this release needs and that those records do
not.

## Decision

- `matches-generated` compares its `version` param with okf's index generator
  revision, `okfIndexGeneratorRevision`, not with the okf release the engine
  runs. The engine depends on `okf` `^0.5.1`, a range inside revision 0.5.0,
  and `engine.okf` reports okf's own `okfVersion`. Guide §§3.1 and 5.6 say
  how. Package format stays 2.
- `KnowledgeWriter.prepare` takes `projectRoot`, the same bound ADR-0018
  gives binding. The search for `wayfinder.json` reads nothing above that
  root, so a bundle with none inside the project is judged by OKF alone.
- `WayfinderProfileResolver.relock` applies an edit of `wayfinder.json` and
  writes the lock for the result under the project's `get` lock. It keeps
  the commits the lock pins, runs no Git, and writes no skill. Before
  writing it refuses an edit the lock does not pin, as `lock-change-required`.
  A file it cannot read or replace is `relock-failed`, and a file it already
  wrote gets its original bytes back where the file system allows.
  `WayfinderConfigEditor.encode(minimal: true)` rewrites only the members the
  edit changed. Registering an actor is that edit. On the command line, an
  edit followed by `wayfinder get` still reuses the locked commit without
  fetching.

## Consequences

A package that sets `version` to `0.5.0`, Bitwild 2026.3 included, loads and
yields the same findings. A host can register an actor without fetching, and
a write stays inside the project the host opened.
