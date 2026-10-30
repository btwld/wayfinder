# Architecture decision log

Accepted choices and their trade-offs; each date is the original decision or
named amendment date. Earlier wording remains in Git history. Existing ADR IDs
are retained for navigation; add future decisions here under titled entries,
without new numbered files. Use 1–3 sentences: what, why and cost.

[README core concepts](README.md#core-concepts) describe the current model.
The [engine contract and schemas](implementation/README.md) govern exact behavior;
[contribution requirements](docs/contributing.md) govern contract/Profile changes.
Specs, API references and runbooks stay separate from this log.

## Publish upstream findings unchanged (ADR-0008)

Date: 2026-08-26; namespace/diagnostic amendment 2026-10-02.

Publish okf's report unchanged and use its finding grammar for Profile results, keeping engine health in separate diagnostics, because translating findings would lose identifiers/severity semantics and create a second wire contract.
Advisories cannot become strict failures, and a Profile finding never enters the OKF report; consumers must read the separate components defined by the [result contract](implementation/okf-implementation-guide.md#41-results-and-exit-codes).

## Local embeddings with Arctic XS (ADR-0009)

Date: 2026-09-09.

Use verified local Arctic Embed XS Q8_0 weights: in [synthetic comparisons](packages/wayfinder_embeddings/fixtures/README.md), XS matched larger Q8 models on 50 of 60 first-context judgments with lower per-query cost, supporting a size/cost choice rather than a general accuracy claim.
Local inference costs model download, startup and disk space; omitting footnote definitions beside ordinary body passages reduces citation competition but can miss useful support, so reviewed regressions or independent-corpus gains should trigger reconsideration.
Retrieval modes were replaced by ADR-0017; model/input identity remains [pinned separately](packages/wayfinder_embeddings/lib/src/embedding/embedding_model_spec.dart).

## Explicit local CLI operations (ADR-0010)

Date: 2026-09-09; dense-only amendment 2026-10-18; encoder/output update 2026-10-20.

Provide one CLI for validation, explicit indexing and cited search so retrieval remains inspectable and separate from Profile conformance; runtime commands never download/train models or implicitly rebuild indexes.
This requires users to reindex after edits and retain derived local copies of bundle text; ADR-0022 replaces the original ObjectBox storage and permits previous snapshots during refresh, while [the CLI guide](packages/wayfinder_cli/README.md) owns current commands.

## Local MCP over shared services (ADR-0011)

Date: 2026-09-09; project-wide discovery 2026-10-16; encoder/output update 2026-10-20.

Expose validate/index/search/graph over local MCP stdio using the CLI's services, because agents need typed discovery/results without implementing another gate or search; default discovery spans project bundles, with an explicit single-bundle override.
Deferring HTTP/authentication and authoring tools keeps the boundary small, but hosts own approval and lifecycle, and per-bundle indexing cannot roll back an earlier publication when a later bundle fails.
[Transport and cancellation details](packages/wayfinder_cli/README.md#mcp-server) remain operational guidance; ADR-0022 governs refresh reads.

## Project the ordinary OKF graph (ADR-0012, ADR-0021)

Date: 2026-09-11; typed edges 2026-10-01; library relocation 2026-10-24.

Project the ordinary OKF graph and add typed relationships beside it, avoiding a competing graph model while exposing the loaded graph to CLI/MCP and embedded hosts.
The projection and `wayfinderLinkFields` live in the project library (ADR-0021), with Profile-agnostic field-list injection into graph/retrieval; this graph is discardable, and consumers needing different semantics must seek a compatibility review rather than treating it as a new source of truth.
[Graph output](packages/wayfinder_cli/README.md) remains okf JSON/Mermaid/DOT plus relationship edges.

## Profile rules are data (ADR-0015, ADR-0024)

Date: 2026-10-01; Ack evaluation 2026-10-07; generator identity 2026-10-24.

Represent Profile rules as schemas over parsed facts or named builtins, with engine-owned finding identity and wording, so authors can change rules without a binary release; a fixture probe reproduced compiled findings and avoided the review/runtime cost of a new expression language.
This limits rules to shared facts/capabilities, requires engine releases for new ones and trusts source-provided regular expressions; bounded package parsing does not bound bundle assessment.
Pin generated-output assumptions to `okfIndexGeneratorRevision`, not the dependency release (ADR-0024), so a generator change requires explicit compatibility/migration review under the [package contract](implementation/okf-implementation-guide.md#56-rules-and-builtins).

## Independent Profile packages (ADR-0016)

Date: 2026-10-02.

Make every Profile an independent package with its own parent and executable conformance rules, because a second corpus needed no Bitwild base and prose authority had made “passes validation but fails the Profile” possible.
Authority is OKF → engine contract → package; README/skills explain judgment, `get` pins sources, and validation reads the local lock/cache, reporting unassessed execution as INCOMPLETE rather than silently passing rules.
This gives up consumer overrides and inherited-rule relaxation: changes need the package/engine release processes, and the flat lock cannot represent two revisions of one id; see [Profile packages](implementation/okf-implementation-guide.md#5-profile-packages).

## Dense-only retrieval (ADR-0017)

Date: 2026-10-18.

Use dense retrieval throughout actual library, CLI/MCP and evaluation searches, removing lexical/hybrid modes and implicit fallback to reduce maintained APIs, fixtures and command contracts; this is a product/maintenance choice, not proof that dense is universally better.
Consumers must supply an embedder and migrate retired arguments, while preview/parsing remain model-free, compatible snapshots remain usable and model failures stay errors.
The [migration/evaluation guide](packages/wayfinder_embeddings/README.md#dense-only-migration) retains generic reranking/context policy and historical evidence attribution; another method needs a concrete need and reviewed quality/cost evidence.

## Embeddable libraries and host ownership (ADR-0018, ADR-0023)

Date: 2026-10-22; host resolution controls 2026-10-24.

Expose project and retrieval behavior as public libraries so IDE/agent hosts need no CLI internals, with injected resources, bounded project roots, typed failures, hardened origin-only Git and checked skill paths (ADR-0023).
Hosts pay for resource lifecycle, fetch consent and serialization: all okf bundle I/O in one process stays on one isolate because its process-owned locks do not exclude isolates, while Wayfinder uses descriptor-owned locks on local disk.
Package parsing normally has a ten-second isolate bound but falls back to unbounded synchronous parsing when spawning fails; hosts needing hard bounds must isolate work themselves, as detailed in [host operating boundaries](packages/wayfinder/README.md#host-operating-boundaries).

## Safe writes with a delta gate (ADR-0019, ADR-0024, ADR-0025)

Date: 2026-10-22; empty commits and shared assessor 2026-10-24.

Keep one prepare/assess/commit path through okf's projection seam, because raw host edits bypassed Profile-generated indexes and caller-authored history; rewrite only indexes whose generated text changes and reject stale bundle/configuration inputs, even for empty commits (ADR-0024).
The whole candidate must pass OKF, but Profile acceptance is a delta with no introduced errors: old errors or an unassessed Profile may remain, so callers needing conformance still require the full gate and may move the shared assessor to a bounded isolate (ADR-0025).
Hosts must serialize relock/get with writes because no lock spans both checks; canonical serialization, leftover lock files and possible rollback failure are costs described in the [authoring API](packages/wayfinder/README.md#authoring).

## Adoption as plan then apply (ADR-0020, ADR-0024, ADR-0025)

Date: 2026-10-22; offline relock and host seams 2026-10-24.

Provide a previewable plan then guarded apply for hosts, approving each fetched source, binding the package's declared id, digesting host inputs and sharing the assessor; offline relock reuses pinned commits without Git or skill writes (ADR-0024/0025).
Planning may populate the external cache, but applying refuses stale/conflicting inputs and holds the project lock across owned writes/undo; failed steps roll back where possible, host writes require host-managed cleanup, and final validation runs after unlock without undoing applied files.
Adoption therefore can remain incomplete after a failed final gate, and existing bindings remain migration work; [adoption API/seeds](packages/wayfinder/README.md#adoption) keep agent configuration and invented concepts outside the library's ownership.

## Immutable plain-file index generations (ADR-0022, ADR-0026)

Date: 2026-10-24.

Replace application ObjectBox indexes with immutable snapshot/vector generations and an atomically replaced current pointer so readers can use the previous publication during refresh without a writer lock; the old HNSW index was unused, so exhaustive scoring preserves ranking behavior.
Search exposes refresh/source-change notices and refuses stale snapshots outside refresh, while every index/prune collects expired generations (ADR-0026); duplicate storage during staging, rebuilds on upgrade, deferred Windows deletion and filesystem-dependent locking remain costs.
[Storage and source notices](packages/wayfinder_cli/README.md#local-storage) remain operational docs, and [model lookup](packages/wayfinder_cli/README.md#embedding-model-lookup) uses explicit override, installed bundle, working/source development models, then verified cache, correcting ADR-0026's former order.
