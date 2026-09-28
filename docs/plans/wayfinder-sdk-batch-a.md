# Wayfinder SDK adjustment — Batch A execution specification

Revision 3 · 27 September 2026

Reviewed code baseline: `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f`.

This is the self-contained execution subset of the complete Flutter/OKF adjustment plan. Only W01, W02, and W03 are assigned to this session. The broader plan also covers candidate validation, interactive retrieval, concurrency, Profile-aware authoring, Flutter editing, and optional capture; those are not part of this batch.

## Problem and decision

The planned Dart/Flutter Markdown editor will use Super Editor and keep Markdown plus OKF authoritative. It needs a supported Dart interface for existing Wayfinder behavior, not imports from CLI internals and not a duplicate validator or retrieval engine.

Extract a supported `wayfinder_sdk` package in this repository. Reuse `okf`, `wayfinder`, and `wayfinder_embeddings`. Use AckInfer for the existing search request. The SDK owns real runtime coordination and operation contracts; the CLI and MCP are adapters. Keep visual editing, original-source preservation, selection, undo, and recovery in the future Flutter app.

This batch is a behavior-preserving extraction. It does not make the full editor runnable or resolve every later SDK design issue.

## Execution authority

Work on an isolated feature branch, never main. Read AGENTS.md, the repository glossary, relevant ADRs, package documentation, and contributor checks before editing. Preserve unrelated work. The reviewed baseline is fixed; the branch may also contain this planning document. If code has changed, record and review the new baseline before proceeding.

You may implement W01–W03, run tests and code generation, commit verifiable slices, push the feature branch normally, and open a draft PR. Do not merge, force-push, tag, publish packages, alter secrets, provision paid services, edit real knowledge bundles, or change another repository. Do not close existing issues #110 or #45. Do not start Batch B after finishing this batch.

Materialize each work item below into a separate local file under `.scratch/wayfinder-sdk/issues/` if a ticket file is useful. Keep this specification as the authoritative active scope. Do not replace the repository's global issue-tracker or agent configuration.

## Existing implementation to inspect

At the reviewed baseline:

- The workspace contains `wayfinder`, `wayfinder_embeddings`, and `wayfinder_cli`; its root generator command currently targets embeddings.
- `wayfinder` owns the closed Concepta Profile validator, layered over OKF. Do not duplicate these rules.
- `wayfinder_embeddings` owns chunking, BM25/dense/hybrid retrieval, snapshots, synchronization, and store/encoder contracts. It directly depends on native-retrieval packages and analyzer; model-free operation is not dependency-free packaging.
- `WayfinderKnowledge` inside the CLI owns bundle/data identity, resource opening, freshness, locks, and completed generations. It is the main extraction candidate.
- The current Ack search schema supplies the nonblank query rule, limit 1–100, and default 5. CLI/MCP handlers still consume map fields.
- Search currently uses dense retrieval with strict freshness and per-call resource lifetime. Preserve that behavior during extraction.

Useful starting paths, to verify against the actual checkout:

- `pubspec.yaml`
- `packages/wayfinder_cli/lib/src/knowledge.dart`
- `packages/wayfinder_cli/lib/src/search_input.dart`
- `packages/wayfinder_cli/lib/src/search_output.dart`
- `packages/wayfinder_cli/lib/src/cli.dart`
- `packages/wayfinder_cli/lib/src/mcp_server.dart`
- `packages/wayfinder_cli/test/knowledge_test.dart`
- `packages/wayfinder_embeddings/lib/src/okf/knowledge_index.dart`
- `packages/wayfinder_embeddings/pubspec.yaml`

## Ownership and invariants

The SDK must hide shared runtime complexity behind a small interface. Do not create an empty facade that re-exports a CLI implementation, or duplicate runtime code in two packages. The SDK must not depend on Flutter or MCP. Existing native dependencies may remain transitively present and must be documented honestly.

Leave command arguments, terminal/JSON presentation, exit-code mapping, MCP registration, installation, updates, and executable-relative discovery in the CLI adapter. Inject explicit locations or a real resource-opening adapter into the shared runtime. Keep one implementation of lifecycle and index policy. A direct consumer must work without relying on the location of the CLI executable.

Reuse existing OKF document, graph, metadata, and finding types. Do not generate parallel SDK versions of the whole domain. Do not make a closed Ack model the authority for arbitrary YAML frontmatter. Search snapshots remain derived data and are not editor documents.

Preserve command/tool names, argument defaults, JSON Schema, output envelopes, errors, source non-mutation, dense mode, stale-index refusal, current locks, per-call close behavior, index identity, and storage schema. Refactoring public Dart ownership does not authorize wire changes. Avoid unrelated formatting or schema churn.

Move tests with behavior. Temporary migration shims are allowed only when necessary to keep intermediate commits coherent; remove them or document their explicit remaining need. Do not force compatible-looking dependency resolution with overrides that violate supported constraints.

## W01 — Use AckInfer for the existing search request

**Blocked by:** None.

**What to build:** A CLI or MCP search request retains its current validation/default semantics but is consumed through a generated typed value. Directly constructed invalid values cannot bypass operation checks.

### Scope

Characterize the existing request and handler behavior first. Add AckInfer using the existing schema as the source of truth. Use typed fields in both adapters. Resolve Ack annotations/generator/build dependencies across the actual workspace. Keep the schema at its current owner until W02 moves it to the SDK, or perform the two steps as explicit verifiable commits.

Use runtime `ack` and `ack_annotations` and development `ack_generator` and `build_runner` as needed. Resolve actual compatible versions instead of choosing each latest version independently. Generate output with the real builder, never by hand. Use the supported two Ack part files and retain generated files according to the repository policy. Read the pinned/resolved generator documentation before relying on generated symbols.

Generated constructors are not immediate validation guarantees. Validate at the operation entry point even when callers constructed a typed request themselves. Do not silently add trimming, coercion, lowercasing, or an unknown-key policy different from the baseline.

### Acceptance

- [ ] Default limit remains 5; limits 1 and 100 pass and out-of-range values fail as before.
- [ ] Missing, blank, and Unicode-only queries; wrong types; explicit null; and unknown keys match characterized baseline behavior.
- [ ] Both CLI and MCP reach the same validated operation behavior.
- [ ] Invalid direct model construction does not bypass checks.
- [ ] MCP JSON Schema, public error/output conventions, and command defaults are unchanged.
- [ ] Real generation succeeds, outputs are retained, and targeted compatibility tests pass.

**Out of scope:** Redesigning graph requests, authoring schemas, search modes, or the entire domain model.

**Evidence:** Before/after contract cases plus one accepted and one refused request through each real adapter.

## W02 — Extract the runtime into a supported SDK

**Blocked by:** W01.

**What to build:** Existing CLI/MCP consumers and a direct Dart consumer use one runtime through public SDK imports. Executable-specific discovery remains in the adapter.

### Scope

Add `wayfinder_sdk` to the workspace, with public exports, documentation, and repository-consistent licensing. Move shared knowledge coordination and its tests into the SDK. Move the generated search contract to its final SDK owner. Inject resource-opening/location behavior. Migrate consumers to public imports and preserve CLI/MCP presentation at the adapter.

Extract graph-loading behavior only when an actual consumer requires it. Keep formatting-only wrappers out of the core; do not add a shallow SDK wrapper solely to call an upstream constructor. Avoid a generic utility package or a replacement storage engine.

### Acceptance

- [ ] CLI/MCP names, arguments, defaults, JSON/text envelopes, and failure mapping remain compatible.
- [ ] Dense mode, strict freshness, locking, resource lifetime, and generation publication are unchanged.
- [ ] A deterministic direct Dart example uses public imports and explicit resource configuration.
- [ ] Migrated production paths do not import another package's private `src` implementation.
- [ ] Existing source-nonmutation, inference-failure, generation, and close behavior is preserved by tests, or an exact environment blocker is reported.
- [ ] No Flutter or MCP dependency is introduced in the SDK.
- [ ] Existing native dependencies are described accurately; no native-free packaging claim is made.
- [ ] There is one runtime implementation, not a copy or a facade over CLI internals.

**Out of scope:** Fixing #110 or #45; a new database; retyping every upstream value; a new Flutter application.

**Evidence:** Adapter contract tests and a direct SDK consumer exercise the same implementation. Inspect moved tests and generated storage changes explicitly.

## W03 — Verify generation, consumer compatibility, and the batch

**Blocked by:** W02.

**What to build:** A maintainer can reproduce generated output, consume the SDK outside monorepo resolution, and review the extraction using recorded evidence.

### Scope

Extend the root build/check entry points for SDK code generation while preserving ObjectBox generation. Use a temporary consumer outside the workspace to expose manifest/import problems. Explicitly configure the SDK package source for this unpublished branch, and record all source overrides; do not use undeclared sibling path resolution to hide a broken manifest. An unpublished local package may require explicit test-only paths, but those must not masquerade as published-version verification.

Run available native checks, and distinguish missing assets from failed checks. Verify no unintended ObjectBox model-ID/storage changes. Review the fixed diff on Standards and Spec, fix in-scope findings, rerun tests, and leave an implementation report.

### Acceptance

- [ ] Dependency resolution succeeds for the selected supported toolchain, or the exact incompatibility is reported.
- [ ] Two successive generation runs are stable; inspect untracked files and ignored outputs as well as tracked diffs.
- [ ] Analyze, formatting, targeted tests, and available full tests have recorded commands, exit status, and evidence.
- [ ] A consumer outside the workspace resolves the explicit test package set and runs the deterministic public-import example.
- [ ] Manifest/source overrides used for unpublished packages are disclosed; no claim of public release validation is made.
- [ ] ObjectBox generation/schema identity is unchanged unless an actual in-scope reason is documented.
- [ ] Base/head, completed tickets, pass/fail/skip counts, platform gaps, and both review axes appear in the report.
- [ ] Independent review is distinguishable from self-review; unavailable runtime/platform evidence is not called a pass.

**Out of scope:** Publishing, tagging, merging, and continuing into later batches.

## Test execution rules

Use the highest practical public seam, shared by tests and consumers. Add a failing behavior test before its implementation where practical. Run narrow tests and analysis throughout. Run the full available suite at the end. Compare against the baseline to distinguish pre-existing failures.

The reviewed root scripts suggest the following commands; verify them in the checkout before use:

```sh
dart --version
dart pub get
dart run melos run build
dart run melos run analyze
dart run melos run format:check
dart run melos run test
```

Also run clean regeneration, an external-consumer smoke test, and package dry-run validation where supported. Dry-run validation is not authorization to publish. Do not remove invalid fixtures, broaden catches to swallow failures, hand-edit generated output, or count native skips as passed tests.

## Fixed-point review and report

Record the actual reviewed base and final implementation SHA. Use their merge-base diff and commit list. Verify a nonempty implementation diff; a planning-only diff is not code completion.

**Standards review:** Read repository rules. Check module ownership, dependency direction, private imports, duplicate implementations, speculative wrappers, resource ownership, generated files, native packaging, and schema identity. Distinguish documented violations from design judgments.

**Spec review:** Map every W01–W03 criterion to evidence. Check input semantics, invalid direct constructors, CLI/MCP compatibility, source non-mutation, reproducibility, independent consumption, and scope creep. Passing lint is not proof of correct behavior.

Separate read-only reviewers may be used at the same fixed base/head. They must not modify the branch while implementation continues. If only the implementer performs the review, explicitly label it self-review. Do not claim independent verification from two headings in one author's report.

Write a report containing: base/head; branch/draft PR; completed and blocked tickets; changed public interfaces; resolved dependencies and test-only overrides; commands and exit statuses; pass/fail/skip counts; logs/CI links; native/platform coverage; Standards findings; Spec findings; fixes/retests; remaining blockers; next eligible work. Mark missing evidence clearly.

Stop after the Batch A report. A draft PR may document partial completion without claiming readiness. Critical compatibility, source-loss, write-safety, or native-resource findings block completion. Do not merge based solely on the summary.

## Deferred sequence, for context only

W04 adds candidate validation without writing. W05 adds explicit session-owned resources. W06 adds revision-aware search during refresh and addresses #110. W07 adds reviewed Profile-aware authoring and addresses the #45 projection decision. The Flutter tasks cover source-safe saving, bounded Super Editor integration, and search/inspector integration in a separately selected app repository. A native-package split and capture/import are optional work, not hidden prerequisites for this batch.

## Sources

- Baseline source: https://github.com/btwld/wayfinder/tree/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f
- Ack generator: https://pub.dev/packages/ack_generator
- Ack model-generation guide: https://concepta.dev/documentation/ack/advanced/typesafe-schemas
- Existing concurrency work: https://github.com/btwld/wayfinder/issues/110
- Existing authoring work: https://github.com/btwld/wayfinder/issues/45

These references explain the baseline and deferred issues. This file is a plan, not evidence that its implementation or checks have completed.
