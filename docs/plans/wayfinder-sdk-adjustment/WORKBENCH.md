# Wayfinder Workbench — minimal desktop app review

Status: draft proposal, not a runnable application. Reviewed 27 September 2026, America/New_York.

Wayfinder code baseline: `5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f`.
Existing planning head before this addition: `7fe58bd4eeb51aace21ae23e64856cd0db673f2f`.
Remix source baseline: `ca0ed4e9173f4fb12f2def558922438a03c877ca`.

This companion proposal narrows the first desktop milestone to pointing at a folder, reading its documents, inspecting validation findings, and understanding failures. It adds a reviewable app direction to the existing draft PR. It does not change the active W01–W03 implementation assignment, add completed tickets, authorize publication, or claim an implementation agent ran.

## Main decision

Build one small Flutter desktop application with Remix as the UI component foundation and its application-owned Vanilla preset as the default look. Keep Super Editor selected for visual editing, but do not make a rich editor or semantic search prerequisites for the first diagnostic build.

The first complete workflow is:

**Open folder → select file → read source/preview → validate saved files → select a finding → inspect source and diagnostic details.**

This is a direct Dart library consumer, not a web app, an MCP client, or a graphical wrapper around shell commands. No login, server, cloud synchronization, or model installation is needed for the first workflow.

## What the Remix review established

The latest published prerelease verified on pub.dev is `remix 1.0.0-beta.10`. The current repository manifest also names beta.10. Do not copy the stale beta.9 Quick Start constraint still present in the published README. Pin beta.10 for the initial application test and commit the resolved app lockfile. Recheck releases when implementation starts; this review is a dated pin, not a permanently current version claim. [R1, R2]

Remix supplies UI behavior with Mix styling and Naked UI interactions. It does not itself supply an application theme. The current preset approach installs editable theme and component source into the application. Vanilla is the CLI default; Fortal is an alternative for Radix Themes-inspired visuals. Choose Vanilla and prefix `Ui` here to minimize custom design work. Do not combine both presets or introduce a separate Wayfinder design-system package. [R3, R4]

The runtime and development floors differ. Remix declares Dart >=3.11 and Flutter >=3.41. The current `remix_cli` source declares version 0.1.0 and requires Dart >=3.12; its README specifies Flutter 3.44 or later and explicitly says the CLI has not been published. Use a pinned Git dependency or pinned local checkout for that CLI until a hosted release is verified. The runtime beta being published does not establish CLI publication. [R2, R4, R5]

Remix is BSD-3-Clause licensed. Retain required notices in installed source and review the actual dependency/license inventory separately; this does not certify every dependency or asset. [R1, R2]

### Proposed setup, to verify in the real application

This is an initial dependency excerpt, not a complete or tested pubspec:

```yaml
dependencies:
  flutter:
    sdk: flutter
  remix: 1.0.0-beta.10

dev_dependencies:
  remix_cli:
    git:
      url: https://github.com/btwld/remix.git
      ref: ca0ed4e9173f4fb12f2def558922438a03c877ca
      path: packages/remix_cli
```

After selecting a Flutter toolchain with Dart >=3.12 and resolving dependencies:

```sh
dart run remix_cli:remix init --prefix Ui --preset vanilla
dart run remix_cli:remix add button textfield tabs badge spinner divider
```

Add dialog/menu/tooltip only when used. The registry includes these items, but their installed constructors and variants must be read from the resulting source, not inferred from older examples. `init` records a separately resolved registry commit in `remix.yaml`. Commit that file, the app lockfile, installed source, and generated adapters according to the app's generated-file policy. A fixed CLI commit does not by itself fix registry content. [R3, R4]

Use `UiThemeScope` with the Vanilla preset. Keep the scope above the Navigator and its overlays through the Flutter host builder. A routed `WidgetsApp` can supply the Navigator/Overlay needed by focused text fields, menus, and dialogs. Keep behavioral roots such as `RemixTabs`; style their children rather than replacing their behavior with unrelated widgets. Read the installed source before assuming names such as a preset-specific Tabs root. [R3]

Do not add `remix_fortal` from an older beta guide. Do not generate a second design system. Changes to local recipes that require Mix code generation use the real generator; AckInfer remains for operation contracts, not visual styles. Verify the complete generator/analyzer dependency resolution when those tools share a package. [R3, R4]

## Smallest useful interface

One window, one selected folder, one selected document. No document tabs or multi-window workspace management in the first milestone.

| Area | Contents |
| --- | --- |
| Top bar | Open Folder, selected root, Refresh, Validate Saved Files, validation scope, appearance control. |
| Left pane | File tree with filename/path filter; errors do not prevent browsing. |
| Center pane | Read-only Source and Preview views of the selected Markdown file. |
| Bottom panel | Problems and Debug tabs; collapsed when unused. |

Metadata can initially appear as a small read-only section in Debug. A permanent right inspector, block toolbar, slash menu, graph canvas, dashboard, and command palette are unnecessary for this first build.

Use the preset's existing spacing, colors, input, button, badge, and focus styles. Do not restyle every widget. Use text labels and icons for error/advisory states, not color alone. Apply the same theme colors and typography to source/preview and later Super Editor through an explicit editor-theme mapping; Remix does not automatically style the editor's internal nodes.

## Folder and validation behavior

The user selects an explicit root. Opening a project directory can suggest its immediate `knowledge/` directory, but must not silently switch roots, scan every sibling project, or treat raw capture directories as OKF bundles. Display the exact selected root and validation scope.

Keep browsing independent from successful OKF parsing. An invalid YAML file must still open as raw source, so the user can diagnose it. An empty folder, missing file, permission failure, and invalid UTF-8 must have distinct messages.

Offer clearly named validation scopes:

- **OKF:** use the existing OKF loader/validator.
- **Concepta Profile:** use the existing `ProfileValidator`, preserving the partitioned OKF/Profile result.
- **Auto:** use the declared Profile when present; otherwise perform the explicitly displayed OKF check. A malformed declaration must be reported rather than silently downgraded to an OKF-only pass.

Plain Markdown remains readable regardless of validation results. Lack of a Concepta declaration is not by itself a reason to reject the folder. Selecting the Profile check explicitly may correctly return an undeclared/unsupported result; do not rewrite that library result into success. [W1]

Display the returned finding code, severity, message, and path. Navigate to a line/range only when the library provides one. Path-only findings open the file without inventing a line number. Directory-wide findings stay directory-wide.

Keep automated checks separate from judgment rules. The current result deliberately reports judgment rules as UNASSESSED; a green automated result must not be labeled complete Profile conformance. Preserve the original structured report for inspection. [W1]

The button validates saved files. Once editing is introduced, show a visible notice when unsaved edits are excluded. Do not save a document merely to validate it. W04 remains the later shared candidate-validation solution.

Mark findings outdated after an observed source change. Tag requests with the selected root and operation generation so a late result cannot replace a newer result or a different folder's state. During validation, detect a changed inventory where practical and report that the sources changed; do not claim a point-in-time snapshot unless the inspected inputs are actually fixed. File watching alone is not proof that every file was read atomically.

## Debugging information

Show application and relevant package versions, selected root, validation mode, operation name, start/end time, duration, result counts, and the original structured report. Keep expected findings separate from operation failures and exceptions.

Later, when retrieval is enabled, add index state, generation identity, model/store availability, busy/stale state, and the actual SDK error. Those fields must reflect real runtime data; do not simulate a working backend or successful checks.

Provide an explicit Copy Diagnostic Report action. Its default export should use relative paths, exclude document bodies and credentials, and retain the information needed to reproduce the failure. Show a preview before copying an expanded report. Keep logs bounded and local. No telemetry or automatic report upload.

A raw report view is data, never instructions to execute. Opening Markdown must not execute code/HTML, fetch remote images, or launch arbitrary URI schemes. Use explicit user actions for permitted external links. Apply a consistent workspace containment and symlink policy to file selection, asset loading, and finding navigation.

## Implementation shape

A proposed home is `apps/wayfinder_workbench/` in this repository. This is a reference/debug consumer, so it need not wait for selection of the eventual product repository. Do not create another repository just to inspect the libraries.

Keep it a separate Flutter package with its own lockfile and Flutter CI job, outside the root Dart Pub workspace initially. The current root workspace uses Dart-based commands and contains the three library/CLI packages. Adding a Flutter app to that resolution without a tooling decision would change development and CI requirements for everyone. Test any local source overrides used to consume unpublished sibling packages; do not rely on accidental workspace resolution. [W2]

Proposed small source layout:

```text
apps/wayfinder_workbench/
  pubspec.yaml
  pubspec.lock
  remix.yaml
  lib/
    main.dart
    workbench_app.dart
    workbench_controller.dart
    workbench_state.dart
    ui/                       # installed Vanilla theme and components
    panels/
      file_tree.dart
      document_view.dart
      problems_panel.dart
      debug_panel.dart
  test/
  integration_test/
```

This is a layout proposal, not files already created.

One controller coordinates folder selection, file loading, validation, and outdated results. Avoid a new routing framework, event bus, generic plugin registry, or many forwarding-only classes. Inject the small amount of filesystem/clock behavior that truly needs controlled testing.

For the read-only slice, call the public `okf` and `wayfinder` libraries directly. Do not add `wayfinder_cli`, `wayfinder_embeddings`, or the future SDK merely to browse and validate. This avoids making native retrieval setup a requirement for the first workflow. It does not claim that the complete later editor/retrieval application is native-dependency-free.

For later index/search operations, consume the supported SDK after W01–W03. Never import CLI `src` files or duplicate its locking/generation logic. Preserve the existing semantic behavior until the appropriate SDK ticket changes it.

Use AckInfer-generated shared requests where available. A proposed export/settings schema can use AckInfer once it becomes a real persistence contract. Do not re-model all OKF findings or transient widget state just to increase code generation.

## Incremental delivery

These are proposed milestones for the companion app, not newly activated entries in the existing twelve-ticket manifest.

| Milestone | End-to-end result | Actual prerequisite |
| --- | --- | --- |
| Read-only diagnostic app | Open folder, source/preview, disk validation, navigate findings, inspect/copy diagnostics. | Remix/toolchain bootstrap and public OKF/Profile library resolution; no SDK extraction requirement. |
| SDK exercise panel | Explicit Refresh Search Index and Search, displaying real errors and citations. | W01–W03 and verified native assets. Initially handle busy/stale failures; do not require or pretend #110 is fixed. |
| Safe source editing | Edit, save explicitly, recover, and validate saved or explicitly supported candidate state. | File-safety acceptance; W04 for shared unsaved candidate validation. Reuses the F01 requirements. |
| Bounded visual editing | Super Editor edits a tested Markdown subset with safe source fallback. | Safe source editing and conversion tests; reuses F02. |

The first milestone can be developed independently without changing Batch A's behavior-preserving scope. A companion app is not an excuse to bundle fixes for search concurrency, Profile authoring, or native packaging into the extraction PR.

Do not block basic navigation/validation on W06. Interactive search during refresh is a later capability; initially show the SDK's actual busy/stale outcome and keep browsing available. Structured Profile-aware authoring still waits for W07/#45. Normal source saves and structured authoring remain separate operations.

## Acceptance and review

Before calling the first milestone complete, verify:

- Open and cancel folder selection; reopen another folder without showing stale results.
- Read a plain Markdown file, a valid OKF file, and a malformed frontmatter file.
- Validate the same fixture through the app and the owning library with equivalent findings.
- Preserve distinction among errors, advisories, unsupported Profile release, operation failure, and unassessed judgment rules.
- Navigate path-only and located findings correctly, including deleted files.
- Observe external changes, revalidate, and never relabel old findings as current.
- Confirm all source-tree bytes are unchanged after browsing, preview, validation, and report export.
- Run with no embedding model or ObjectBox setup for the first read-only workflow.
- Test keyboard traversal, text selection, scrolling, text scaling, and both appearance modes on the actual development desktop.
- Resolve the pinned CLI and registry, run real generation, check a clean second run, and record dependency versions.
- Confirm root Dart-only checks and independent Flutter checks still run in their intended environments.

Standards review checks ownership, minimalism, token use, host capabilities, public imports, generation policy, and absence of hidden runtime dependencies. Spec review checks the complete folder-to-finding workflow, source non-mutation, truthful status, and scope. Label author review as self-review unless a separate reviewer actually ran.

## Verification limits of this review

Repository manifests, the Remix usage/CLI guides, the published beta page, the existing adjustment plan, and the Profile validation implementation were read. No Flutter or Dart executable is available in the authoring environment. No application, dependency solver, code generator, desktop build, widget test, or native runtime test ran. CLI hosted publication was not established; the inspected source explicitly marks it unpublished. The proposal remains in draft.

## Sources

- R1: Published Remix beta.10: https://pub.dev/packages/remix/versions/1.0.0-beta.10
- R2: Remix manifest: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/packages/remix/pubspec.yaml
- R3: Current usage guide: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/skills/using-remix/SKILL.md
- R4: CLI setup, publication state, and registry behavior: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/packages/remix_cli/README.md
- R5: CLI SDK floor: https://github.com/btwld/remix/blob/ca0ed4e9173f4fb12f2def558922438a03c877ca/packages/remix_cli/pubspec.yaml
- W1: Existing Profile result and validation contract: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/packages/wayfinder/lib/src/validation.dart
- W2: Existing root workspace: https://github.com/btwld/wayfinder/blob/5a8f0f5abf6ebeb7927a39ae044215ae2a99ca7f/pubspec.yaml

Related plan: [ADJUSTMENT.md](ADJUSTMENT.md). Active SDK scope: [Batch A](../wayfinder-sdk-batch-a.md). Current execution history: [STATUS.md](STATUS.md).
