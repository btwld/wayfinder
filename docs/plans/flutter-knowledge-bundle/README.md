# Flutter and Dart knowledge bundle: agent handoff

Status: proposed implementation plan. No importer or public knowledge bundle is
implemented by this planning change. The JSON files here are planning inputs and
an example, not installed Wayfinder configuration or generated lockfiles.

## Goal and foundation

Build a public, source-attributed OKF example that connects Dart and Flutter agent
skills, architecture, terminology, release changes, migration guidance, and selected
design rationale. Provide a repeatable Dart importer and demonstrate the resulting
bundle with existing Wayfinder validation, search, graph, and MCP services.

The format foundation is [PR #113](https://github.com/btwld/wayfinder/pull/113),
branch `feat/config-json`, reviewed at commit
`7d9ed505a8b300ca5ba0959c058f02873a0333e3`. It proposes **Bitwild Profile 2026.3,
OKF 0.2 exactly**. It is not a claim that 2026.3 has been merged or published.
This handoff is stacked directly on #113, not on `main`. The unrelated workbench,
session-memory, and ADR-cleanup PRs are not dependencies.

A future implementation must re-read the actual base revision before changing
files. If #113 changes, reconcile the contracts here against that revision. If it
is merged by squash or rebase, use its actual merged successor and verify the
format again; do not silently keep an obsolete draft selector.

## Contents

| File | Purpose |
| --- | --- |
| [AGENT.md](AGENT.md) | Execution prompt, ordered work, validation commands, and one-commit PR delivery |
| [DESIGN.md](DESIGN.md) | Import contracts, reconciliation, provenance, version handling, and safety |
| [ACCEPTANCE.md](ACCEPTANCE.md) | Required tests, semantic evaluation, and completion gates |
| [sources.plan.json](sources.plan.json) | Source allowlist and bounded discovery policy; not a resolved source lock |
| [wayfinder.example.json](wayfinder.example.json) | Direct-source 2026.3 configuration example pinned to the reviewed foundation |

## Implementation boundary

Use `tool/knowledge_import/` for an independent, non-published Dart tool package.
Use `examples/flutter-knowledge/` for the self-contained public demonstration
project. Its only OKF bundle is `examples/flutter-knowledge/knowledge/`.
The example is public technical reference material, not client or internal project
knowledge. Do not read Notion, email, chats, or private repositories for this work.

Keep the importer separate from the existing Profile resolver. Do not change the
Profile, add frontmatter fields, expand the graph schema, replace retrieval,
introduce new MCP tools, or register a source-synchronization command in the main
Wayfinder CLI. No provider API key, hosted model, scheduled task, or service account
is necessary for the first implementation. A coding agent performs the semantic
authoring step; the importer handles evidence and reviewable changes.

The first vertical slice covers five named skills, framework and application
architecture, terminology, and one explicitly selected historical migration.
After that slice passes, expand to the complete two skill catalogs, a frozen window
of three stable Flutter release families and their relevant breaking changes,
corresponding released Dart changes, and a small reviewed design-document set.
Missing or rights-blocked material must remain visible as a coverage gap, never
silently omitted while claiming full completion. Concept count is not a target.

## Format requirements from the foundation

The controlling sources are the [Profile](../../../profile/okf-profile.md),
[configuration guide](../../wayfinder-configuration.md),
[implementation guide](../../../implementation/okf-implementation-guide.md),
[pinned OKF text](../../../skills/author-knowledge-bundle/references/OKF-0.2.md),
and [authoring skill](../../../skills/author-knowledge-bundle/SKILL.md).
These links follow the checked-out branch; the reviewed baseline is identified
above. The plan is subordinate to them, not a new Profile specification.

Use the direct `source` plus `applies_to` shape under `profiles.bitwild_profile`.
Generate and commit `wayfinder.lock` with `wayfinder get`; never fabricate it.
Only `index.md` and `log.md` are required bundle-root files in 2026.3. Do not seed
legacy `profile.md`, `types.md`, or `actors.md`. The root index declares
`okf_version: "0.2"`. Standard types come from the selected Profile; declare only
needed additional types, topic tags, and actual actor lookup in project JSON.

Keep project areas subject-named and earned by real content. A migration about
navigation belongs with navigation, not in a generic `migrations/` directory.
Use existing Profile relationship labels when their meaning fits. The existing
ordinary OKF graph returns body links as untyped edges; labelled Markdown does not
create a typed reasoning engine. Do not report typed graph-query support.

## Source and rights evidence

The upstream [Flutter catalog](https://github.com/flutter/agent-plugins/blob/main/README.md)
and the [Dart](https://github.com/dart-lang/skills/blob/main/resources/dart_skills.yaml)
and [Flutter](https://github.com/flutter/agent-plugins/blob/main/resources/flutter_skills.yaml)
generator manifests provide discovery inputs. Preserve both the manifest recipe
and its corresponding generated skill as evidence. They are not necessarily
identical; neither should overwrite the other during import.

Architecture sources include the [framework overview](https://docs.flutter.dev/resources/architectural-overview),
[Inside Flutter](https://docs.flutter.dev/resources/inside-flutter), and
[application guidance](https://docs.flutter.dev/app-architecture).
The [glossary](https://docs.flutter.dev/resources/glossary),
[release notes](https://docs.flutter.dev/release/release-notes),
[breaking-change guides](https://docs.flutter.dev/release/breaking-changes),
[Dart SDK changelog](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md), and
[contributor guidance](https://docs.flutter.dev/contribute) cover the other inputs.
The manifest records which backing paths still require discovery at execution.

The observed repository defaults are BSD-3-Clause for the
[Dart skills](https://github.com/dart-lang/skills/blob/main/LICENSE),
[Flutter skills](https://github.com/flutter/agent-plugins/blob/main/LICENSE),
[Flutter SDK](https://github.com/flutter/flutter/blob/main/LICENSE), and
[Dart SDK](https://github.com/dart-lang/sdk/blob/main/LICENSE).
The [Flutter website license](https://github.com/flutter/website/blob/main/LICENSE)
specifies CC BY 3.0 for content and BSD terms for code samples; the
[Dart website license](https://github.com/dart-lang/site-www/blob/main/LICENSE)
specifies CC BY 4.0 and BSD-3-Clause respectively. These observations do not clear
individual files, linked documents, images, or copied third-party examples.
Recheck notices at the locked revisions. Openly available is not public domain.

Retain upstream copyright, conditions, disclaimers, attribution, license links,
and change notices as applicable. Keep notices with downloadable/exported bundles.
Do not describe Google, Dart, or Flutter as endorsing the derivative. Do not
replace third-party terms with this repository's Apache license. A source with
unclear rights is link-only pending review, not automatically redistributable.

## Evidence for this planning change

Repository inspection used the connected GitHub tools. The reviewed foundation's
configuration, schema, Profile, seeds, authoring instructions, mirroring rules,
relationship rules, and workspace manifest were read. Public source entry points
and repository license notices were checked. Local JSON, link, and whitespace
checks apply only to this handoff and are reported in the PR.

The authoring environment has Git but no Dart or Flutter executable. Direct GitHub
cloning failed DNS resolution. No Dart tool was compiled or run, no `wayfinder.lock`
was generated, no knowledge bundle was authored, and no retrieval or MCP test ran.
A passing planning check or an upstream PR's test report is not implementation
verification for this work. No agent has been launched by saving this handoff.
