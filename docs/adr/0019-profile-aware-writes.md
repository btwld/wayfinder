# ADR-0019: Profile-aware writes

- Status: accepted
- Date: 2026-10-22
- Updated: 2026-10-22 (content stamps, finding deltas and captured project files)
- Scope: prepare/assess/commit, generated files and stale plans; no Profile rule
- Driver: [#45](https://github.com/btwld/wayfinder/issues/45): raw edits bypassed Profile-aware projection
- Builds on: [0015](0015-profile-rule-catalogs.md), [0018](0018-embeddable-libraries.md)
- Amendments incorporated: [0024](0024-generator-revision-and-offline-relock.md) and [0025](0025-host-adoption-seams.md)

## Context and decision

Keep one transaction path: `KnowledgeWriter` in `package:wayfinder/authoring.dart`
uses okf's prepare/projection/commit seam rather than maintaining a second writer.
`prepare` writes nothing, projects reserved files, and assesses the in-memory
candidate. `commit` writes the bound bytes under okf's exclusive bundle lock.

Links append `relationships` entries with bundle-relative resources. With fixable
Profile rules, rewrite only indexes whose generated text differs between base
and candidate, preserving unrelated stale indexes. Explicit `RegenerateIndexes`
repairs all stale generated indexes, as `validate --fix` does. Without a fixable
rule, okf's ancestor regeneration stands. Caller-authored log entries preserve
existing style where possible; no content change means no entry. The engine
invents no Profile-specific lead words.

A `KnowledgeStamp` supplies provenance: creating/changing body, title, description
or type updates `generated`; links and other metadata preserve it. Verified stamps
append verification. Callers cannot supply those provenance fields directly.
`changesConceptContent` exposes this rule so hosts do not duplicate it.

## Assessment and commit boundaries

The OKF gate covers the whole candidate. The Profile gate is a **delta**: findings
match the base by rule id and path as a multiset; introduced errors/diagnostics
refuse the plan. A committable write can retain old errors. Without a selected
Profile, the delta may be empty and the result remains `NOT_ASSESSED`, never
`PASS`; hosts decide whether to allow unassessed writes. Full conformance requires
checking the candidate's gate. The plan also reports the OKF finding delta without
replacing okf's whole-candidate gate.

Assessment runs after the shared bundle claim is released. `KnowledgeAssessor`
receives plain loaded data and selection; hosts may use `assessWithin` to bound
rules on a killable isolate. Bundle I/O still follows ADR-0018's single-isolate
rule. Cancellation is checked between steps, never during okf's transaction.

Commit rejects changed bundle snapshots and captured configuration/lock files,
including previously absent closer configurations. Hosts selecting Profiles
themselves pass the files and digests captured with that selection. An unreadable
existing project file is `write-failed`, not absent. Even an empty diff takes the
exclusive lock, checks staleness and consumes the plan without rewriting documents.
`projectRoot` bounds binding. There is no atomic lock spanning project resolution
and bundle commit; hosts that relock/get and write must serialize those operations.

## Consequences

The same validator judges writes and validation, but delta acceptance does not
guarantee a passing full gate. Refusals identify findings/paths. Changed concepts
may acquire okf's canonical frontmatter layout; other files retain bytes.
`write-failed` reports rollback failure and possible partial writes. Commit and
writing `--fix` leave `.okf.lock`; a no-op fix takes no lock. A fix lock failure is
`wayfinder/fix-failed` with nothing written.

There is no MCP authoring tool, move or delete operation. See the
[authoring API](../../packages/wayfinder/README.md#authoring). Reconsider for new
okf change types or Profile-generated files beyond indexes.
