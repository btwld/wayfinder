# ADR-0020: Programmatic adoption as plan, then apply

- Status: accepted
- Date: 2026-10-22
- Scope: adoption library, generic seeds, configuration editing and fetch policy
- Builds on: [ADR-0018](0018-embeddable-libraries.md)
- Amendments incorporated: [0024](0024-generator-revision-and-offline-relock.md), [0025](0025-host-adoption-seams.md)

## Context and decision

Hosts need the adoption skill's setup in process, with a preview before project
writes. `KnowledgeAdoption.plan` resolves Profiles and lists exact writes/digests,
fetches, locked chain, skills, conflicts and predicted validation. Planning may
populate the external Profile cache but writes nothing in the project. Fetch
policy approves each source, including parents discovered only after reading a
child; offline requests refuse fetches. No-ref requests bind the resolved commit;
explicit refs retain the ref and lock its commit.

`apply` refuses conflicts or changed project, bundle, skill or cache inputs before
writing. It holds the project's `get` lock across checks, writes and undo; busy
projects fail immediately. It stages a seeded bundle, writes binding/lock/skills
and the ignore line, then runs an optional host step. Failed write steps undo in
reverse where possible; undo failure is explicit. Final validation runs after
lock release and **does not undo writes**: a non-PASS gate leaves adoption
incomplete. Host writes need the host's own undo implementation.

Adoption writes only Wayfinder-owned files, never agent instructions, MCP config
or hooks directly. It returns a `Knowledge bundle` instruction block for the host.
Unmarked skill directories and marked directories it would orphan are conflicts.
`KnowledgeSeeds` and SEEDING's literal examples are parity-tested. Seeds include
only requested root files and host-supplied concepts; adoption invents none.
Existing OKF-valid bundles can be bound unchanged; a directory containing only
`.okf.lock` counts as empty. Generated-index rules shape seeded indexes.

## Host seams (0024–0025, 2026-10-24)

Bind by the package's declared id at the resolved commit; a conflicting requested
id fails before writes. Share the writer's assessor; `assessWithin` can bound rule
assessment, while seed-index generation remains on the calling isolate. Host input
files join staleness checks. Reject literal `..` before symlink resolution and
reject targets outside the project, the root itself or `.git`.
Step listeners can fail starting/ending steps; exceptions during failure reporting
or the host step's final `done` notification are ignored.

Configuration encoders preserve unmodeled values. `relock` edits configuration and
lock under the project lock without Git or skill writes, retaining pinned commits;
unpinned edits fail `lock-change-required`. File errors are `relock-failed`, with
best-effort restoration of earlier bytes. Minimal encoding changes only edited
members; actor registration is one use.

## Consequences

Hosts can preview setup without taking over agent configuration. Existing bindings
remain migration work, not adoption. Cache writes survive failed planning/apply,
rollback can fail, and a failing final gate leaves applied files for repair.
The host still places the instruction paragraph before adoption is complete.
See the [adoption API](../../packages/wayfinder/README.md#adoption).
