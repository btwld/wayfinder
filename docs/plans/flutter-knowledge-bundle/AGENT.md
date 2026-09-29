# Agent execution prompt

Implement the public Flutter and Dart knowledge importer and example described in
[README.md](README.md), [DESIGN.md](DESIGN.md), and [ACCEPTANCE.md](ACCEPTANCE.md).
The user authorized either implementation or an agent-ready plan, with all delivered
changes in one commit and a pull request. This directory is that planning handoff;
execute it only when assigned to an implementation agent.

## Read and preserve the foundation

1. Read repository `AGENTS.md`, this entire handoff, the Profile and implementation
   guide, and the authoring skill with its routed references. Read the real files,
   not only this plan's summaries.
2. Inspect PR #113 and the branch/commit on which this handoff sits. Record the exact
   base. Use the 2026.3 direct-source configuration, not the old 2026.2 root files or
   an unpublished `bundles`/`implements` shape. Do not merge or alter #113.
3. If working directly on the handoff branch, first confirm it has no unrecognized
   edits or newer contributions. Preserve this plan and combine your own changes
   into its single commit only when assigned to update this PR. Otherwise create a
   separate implementation branch from the verified foundation and include this
   handoff in the one implementation commit. Do not force-push a shared branch to
   remove other work. Never infer permission to merge either PR.
4. Check Dart (repository minimum 3.11.0), Git, and the native search runtime. Use the
   stable Dart formatter required by this repository. Missing native libraries
   block native demonstration claims, not deterministic importer development.

## Ordered work and completion evidence

| ID | Depends on | Work | Required evidence |
| --- | --- | --- | --- |
| F01 | none | Reconcile foundation and freeze source selection | Exact Profile revision; rights-aware source inventory; explicit release list |
| F02 | F01 | Build source resolver, lock, cache, and safe network/file boundary | Local-Git and HTTP-fixture tests; moved-ref, corrupt-cache, and path tests |
| F03 | F02 | Implement skill, documentation, glossary, release, and design-evidence adapters | Pinned fixtures; spans and hashes; complete/partial state; duplicate handling |
| F04 | F03 | Produce and reconcile the pilot with the authoring skill | Five skills plus the scoped supporting corpus; justified concept identities; provenance map |
| F05 | F04 | Implement controlled apply and deterministic index projection | Golden tests against Profile rules; conflict, rollback, no-op, and log tests |
| F06 | F05 | Validate and evaluate through existing Wayfinder | Independent OKF result; Profile result and contextual review; graph/search/MCP evidence |
| F07 | F06 | Expand to all planned source families and package the demonstration | Coverage inventory; rights notices; explicit gaps; rerun evaluation and single-commit PR |

Keep one integration owner. F02/F03 can use helper agents only within separate
files after the contracts are settled; they must not concurrently edit canonical
concepts, indexes, logs, locks, or the publication transaction. Do not activate
unrelated SDK/workbench/session-memory plans in other PRs.

## Concrete implementation destinations

Create a non-published standalone package at `tool/knowledge_import/`, with its own
`pubspec.yaml`, CLI entrypoint, library, schemas, and tests. Do not add it to the
workspace until the need is established; document its independent test command.
Use public APIs from the repository's validation packages where appropriate, with
path dependencies during development. Do not import their private `src/` classes
or duplicate the Profile resolver. Package dependency versions must be resolved
and tested in the actual implementation environment.

Create `examples/flutter-knowledge/` containing the example README, project
configuration and generated Profile lock, import manifest and content lock,
provenance map, attribution/licenses, evaluation cases, and `knowledge/`.
Ignore raw source cache, staging, credentials, native binaries, models, and search
indexes. Do not modify `examples/knowledge/` or migrate its legacy release.

Use [sources.plan.json](sources.plan.json) to build the reviewed runtime manifest.
Resolve selectors to real files at full Git commits before extraction. Record
unresolved backing files rather than treating guessed paths as verified. Resolve
the glossary's data/template source instead of assuming `resources/glossary.md`.
The plan schema itself is not a released importer API.

## Required first slice

Select these existing skills by name, not a positional catalog slice:
`dart-add-unit-test`, `flutter-add-widget-test`,
`flutter-apply-architecture-best-practices`, `flutter-build-responsive-layout`, and
`flutter-fix-layout-issues`.

Add framework overview, Inside Flutter, the minimum application architecture pages
needed by that skill, relevant glossary entries, and one verified historical
migration connected to a selected concept. Inspect the actual migration before
choosing a release or replacement claim. Do not invent a new skill for a desired
subject; use additional allowed documentation if a skill does not exist.

Retain source differences. For example, a skill's strict instruction to use a
particular state mechanism must not become a universal Flutter requirement merely
because a broader architecture guide discusses it. Represent scope, alternatives,
and unresolved contradictions explicitly. Never claim a proposal shipped solely
because an issue is closed or a design document exists.

## Proposed importer interface

The following is the interface to implement, not commands available in this PR.
Use an entrypoint at `bin/knowledge_import.dart`. From the repository root:

```sh
cd tool/knowledge_import
dart pub get
dart run bin/knowledge_import.dart resolve --project ../../examples/flutter-knowledge
dart run bin/knowledge_import.dart plan --project ../../examples/flutter-knowledge
# An assigned authoring agent edits and reviews the staging change set here.
dart run bin/knowledge_import.dart apply --project ../../examples/flutter-knowledge --changeset <reviewed-changeset>
dart run bin/knowledge_import.dart check --project ../../examples/flutter-knowledge
cd ../..
```

Implement `upgrade` as the only command that deliberately advances a locked mutable
ref. `plan` and `check` work offline against a complete locked cache. None of these
commands runs instructions embedded in downloaded skills. `apply` requires exact
baseline hashes and an explicit reviewed change-set path; no blanket overwrite or
implicit publication. See DESIGN for the separate transaction and freshness rules.

## Validation using the foundation

From the repository root, after implementation and seeding the example:

```sh
dart pub get
dart analyze --fatal-infos
(cd packages/wayfinder && dart test)
(cd packages/wayfinder_cli && dart test)
(cd packages/wayfinder_embeddings && dart test)
(cd tool/knowledge_import && dart analyze --fatal-infos && dart test)
dart format --output=none --set-exit-if-changed tool/knowledge_import/bin tool/knowledge_import/lib tool/knowledge_import/test
dart run wayfinder_cli:wayfinder get examples/flutter-knowledge
dart run wayfinder_cli:wayfinder validate examples/flutter-knowledge/knowledge --output json
dart run wayfinder_cli:wayfinder graph examples/flutter-knowledge/knowledge --output json
dart run wayfinder_cli:wayfinder graph examples/flutter-knowledge/knowledge --output mermaid
```

Read the current installation and CLI guides before running native `index`,
`search`, and `mcp`; source execution alone does not establish that native libraries
and model files are staged. Use the installed runtime or the repository-supported
native setup. Run the evaluation harness described in ACCEPTANCE with that exact
runtime and model. `mcp` uses its stdio protocol, not a browser HTTP endpoint.

Run the existing released-2026.2 and configured-2026.3 regression gates documented
in CI. Do not copy a lock from the synthetic local-Git fixture into the public
example. Perform contextual Profile Review after the atomic bundle write. Never
add `verified` metadata simply because these automated checks pass.

## Deliver exactly one commit and a PR

Inspect all changed files and run `git diff --check`. Stage only the importer,
example, related tests/documentation, and necessary CI integration. Exclude local
caches, raw downloads, user material, secrets, runtime indexes, and unrelated files.

Before pushing, compare against the actual chosen PR base and verify exactly one
new commit. For a new branch use a normal push. Updating a previously pushed
single-commit implementation requires an amended/squashed commit and
`--force-with-lease` only on the dedicated branch after confirming ownership and
absence of other contributions; never force-push `main` or the foundation branch.

If #113 remains open, target its `feat/config-json` branch and mark the dependency
in the PR. After it merges, retarget/rebase using the actual merge result and
recheck the one-commit diff; do not automatically merge the stack. If continuing
this planning PR, update its title/body to reflect the real implementation state
only after implementation evidence exists.

The PR body must state source revisions, covered and blocked corpus, rights review,
Profile resolution, tests passed/failed/skipped, semantic evaluation, no-op update
results, and remaining work. Keep it draft while a required gate is unmet. A plan,
fixture-only test, downloaded model, or successful search is not proof of the
whole workflow. Do not call a partial implementation complete.
