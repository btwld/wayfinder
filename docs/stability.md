# The 1.0 compatibility contract

This is the prepared contract for the first 1.0 release of each of Wayfinder's
four packages. A prepared version is not a published release. The packages
remain independently versioned; a Profile's own release is independent of all
four. [Release preparation](releasing.md) and exact-source verification still
decide whether a candidate can ship.

## Supported surfaces

| Package | Public surface |
| --- | --- |
| `wayfinder` | [`wayfinder.dart`](../packages/wayfinder/lib/wayfinder.dart), [`project.dart`](../packages/wayfinder/lib/project.dart), [`adoption.dart`](../packages/wayfinder/lib/adoption.dart), and [`authoring.dart`](../packages/wayfinder/lib/authoring.dart), including their exported types, failure codes, cancellation and host-injection seams. The Git and file-lock helpers exported by `project.dart` are included. |
| `wayfinder_embeddings` | [`wayfinder_embeddings.dart`](../packages/wayfinder_embeddings/lib/wayfinder_embeddings.dart), [`okf_knowledge.dart`](../packages/wayfinder_embeddings/lib/okf_knowledge.dart), [`knowledge_store.dart`](../packages/wayfinder_embeddings/lib/knowledge_store.dart), [`model_cache.dart`](../packages/wayfinder_embeddings/lib/model_cache.dart), and test-only [`testing.dart`](../packages/wayfinder_embeddings/lib/testing.dart). Custom chunker, encoder, searcher and storage extension points are included. |
| `wayfinder_dart_chunker` | [`wayfinder_dart_chunker.dart`](../packages/wayfinder_dart_chunker/lib/wayfinder_dart_chunker.dart): `DartChunker` and `defaultCodeRegistry`. |
| `wayfinder_cli` | The documented `wayfinder` commands, options, exit meanings, JSON/SARIF output, MCP tool names and input/output contracts, installer settings and update behavior in the [CLI guide](../packages/wayfinder_cli/README.md) and [installation guide](install.md). This package has no public Dart library entry point. |

Imports under `lib/src`, generated ObjectBox bindings, build/evaluation scripts,
and the illustrative examples are not additional supported Dart entry points.
An example teaches the public API it uses; it does not establish another API.
`testing.dart` exercises mechanisms and does not supply a relevance baseline.

## What compatibility preserves

- **Dart callers:** the public names, signatures, type constraints and documented
  extension/implementation points, and their documented effects, ownership and
  failure semantics. Adding an enum value or a sealed subtype can break an
  exhaustive caller; it is not automatically a harmless addition.
- **Machine consumers:** documented command/tool inputs, required output fields
  and their meanings, finding and diagnostic identities, stable failure codes,
  and documented ordering and exit values. Added response fields are compatible
  only where the owning contract permits extension. Closed sets are not silently
  opened. Human-readable wording, timings and floating-point similarity bits
  are not substitutes for the machine identifiers and values.
- **Profile authors:** OKF takes precedence over the engine guide and schemas,
  which take precedence over a Profile package. The guide's package `format`
  dispatch, fact/check meanings, composition and diagnostic rules govern every
  Profile equally. All inherited rules use the effective chain/project
  vocabulary; additions may change findings but cannot override an inherited
  rule's definition or severity. A package interpretation change follows the
  [contract-change process](../AGENTS.md#changing-the-engine-contract), including
  a format bump when an existing package would read differently.
- **Agent integrations:** generic skill names and the CLI installation/status
  operations remain part of the application surface. Profile skills are pinned
  to their project's lock. Skills guide judgment, not a second conformance gate;
  their prose may improve without creating a new validator requirement.

A breaking public-surface change needs a major package release and a migration
entry naming affected callers or data. A fix, dependency upgrade, or internal
refactor is not evidence of preservation by itself: the relevant contract and
regression checks must still pass. Profile rules and vocabulary change through
that Profile's release process, not through a CLI patch.

The [engine guide](../implementation/okf-implementation-guide.md), package
guides and schemas define details once. This document identifies the stability
boundary; it does not replace those contracts or add a rule to a bundle.

## Host ownership and operational limits

The existing host obligations remain part of the API. Hosts own injected
resources and their documented disposal; model acquisition is explicit.
Project roots bound discovery, plans refuse stale inputs, and host-owned writes
are not silently included in a filesystem transaction. All okf bundle I/O in
one process stays on one isolate; only the documented assessment seam moves
work elsewhere. Respect the serialization and rollback limits in the
[core guide](../packages/wayfinder/README.md) and the index publication/cancellation
limits in the [retrieval guide](../packages/wayfinder_embeddings/README.md).

Search returns candidate passages with citations, not generated answers or a
guarantee of authority, freshness, relevance or deterministic ordering among
equal-scored candidates. The documented freshness policies and notices still
apply. No latency, availability, corpus-size or retention service level is
introduced by a 1.0 version.

## SDK and native verification

The prepared packages declare Dart `>=3.11.0 <4.0.0`. The source matrix checks
Dart 3.11.0 and stable on Linux and Windows; stable is the canonical formatter.
Required native tests, relocated CLI/MCP probes, the judged retrieval gate and
no-Dart installer checks cover these prebuilt targets:

| Target | Native source-CI leg |
| --- | --- |
| Linux x64 | Ubuntu runner, Dart stable and 3.11.0 |
| macOS ARM64 | macOS runner, Dart stable |
| Windows x64 | Windows runner, Dart stable |

The [CI workflow](../.github/workflows/ci.yml) is the executable matrix.
Installer checks additionally cover PowerShell 7 and Windows PowerShell 5.1.
These are tested target combinations, not a claim that every historical OS
version or another CPU/backend works. Other native combinations need their
own verification before a prebuilt release is offered. Source SDK constraints
do not provision native libraries or model weights in a consuming application.

A release records the actual tested SDK and runner/platform results. Local
macOS results do not stand in for Linux, Windows or the designated independent
SARIF schema-validation leg. Changes to declared SDK floors or offered native
targets are explicit compatibility decisions with release notes, not silent
changes to this matrix.

## Data and migrations

User knowledge, project configuration, the revision lock and installed Profile
skills are not disposable caches. Keep their documented meaning and ownership;
incompatible format changes need explicit selection/migration and must not
silently rewrite or reinterpret them. An unsupported Profile is not partly
assessed and a missing assessment cannot become `PASS`.

Indexes, downloaded model caches and source mirrors are rebuildable derived
state. This does not authorize deleting user knowledge or ignoring documented
update/repair behavior. A change to model/preprocessing identity, chunk inputs,
runtime identity, index configuration or a storage schema must take the owning
format/identity path: reject incompatible data or rebuild under the documented
new identity, rather than reuse incompatible vectors. A changelog names any
required reindex or reinstall. There is no promise that private cache paths or
all generations are retained forever. An older ObjectBox store's compatibility
is the specific migration the retrieval package documents and tests, not a
promise for every possible future database schema.

Release readiness is established by the [release preflight](releasing.md#release-preflight)
and the remaining staged distribution checks, not by this document alone.
