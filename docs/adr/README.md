# Architecture decision records

ADRs record why the engine and its tools are shaped the way they are. The
[OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md),
the [engine contract](../../implementation/okf-implementation-guide.md), and
each Profile package govern behavior, in that order. An ADR explains a
decision; it adds no requirement. These records describe this repository's
architecture, not decisions inside a project's knowledge bundle.

Each record states the decision as it was accepted. A later change is a new
record with `Amends:` or `Supersedes:` pointing at that record. Git history
and the guide's §9 change record keep what came before. A Profile's own
rationale lives in its package, such as the
[Bitwild README](../../profiles/bitwild/README.md).

## Record format

A short header with `Status`, `Date`, and `Scope`. A record that changes an
accepted one also has `Amends:` or `Supersedes:`. Then `Context`, `Decision`,
and `Consequences`. Add `Options considered` or `Reconsider when` only when
they carry distinct evidence. Commands and dependency details belong in the
relevant guide; an ADR records the durable choice and links there.

## Catalog

Numbers are stable references. Gaps reflect retired records; do not renumber
the remaining records or reuse a retired number. Append new records instead.

The last column links later changes to a decision. Read those for the amended
part; the original record still explains the rest. For current behavior, use
the engine contract and package guides.

| ADR | Decision | Later changes |
| --- | --- | --- |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Preserve okf's finding report and use its grammar for Profile findings | [0016](0016-independent-profile-packages.md) |
| [0009](0009-local-knowledge-retrieval.md) | Arctic Embed XS for local embeddings | [0017](0017-dense-only-retrieval.md) (retrieval defaults only) |
| [0010](0010-wayfinder-cli.md) | One CLI for validation, indexing, and local search | [0017](0017-dense-only-retrieval.md) (modes), [0022](0022-plain-file-index-generations.md), [0026](0026-model-cache-and-source-paths.md) |
| [0011](0011-wayfinder-mcp.md) | Project-wide tools over local MCP stdio | [0022](0022-plain-file-index-generations.md) |
| [0012](0012-wayfinder-graph-projection.md) | Ordinary OKF graph plus typed relationship edges | [0021](0021-graph-projection-in-project-library.md) |
| [0015](0015-profile-rule-catalogs.md) | Profile rules as schemas over facts or named builtins | [0023](0023-host-resolution-seams.md), [0024](0024-generator-revision-and-offline-relock.md), [0027](0027-shared-effective-vocabulary.md), [0029](0029-profile-neutral-directory-facts.md) |
| [0016](0016-independent-profile-packages.md) | Independent Profile packages, selected and enforced equally | [0027](0027-shared-effective-vocabulary.md), [0029](0029-profile-neutral-directory-facts.md) |
| [0017](0017-dense-only-retrieval.md) | Dense-only retrieval; retain generic reranking and context | — |
| [0018](0018-embeddable-libraries.md) | Embeddable libraries, host-owned resources, bounded roots, and locking | [0020](0020-programmatic-adoption.md), [0022](0022-plain-file-index-generations.md), [0023](0023-host-resolution-seams.md), [0024](0024-generator-revision-and-offline-relock.md), [0026](0026-model-cache-and-source-paths.md) |
| [0019](0019-profile-aware-writes.md) | Profile-aware writes through okf's transaction | [0024](0024-generator-revision-and-offline-relock.md), [0025](0025-host-adoption-seams.md) |
| [0020](0020-programmatic-adoption.md) | Adoption as plan, then apply, with rollback | [0024](0024-generator-revision-and-offline-relock.md), [0025](0025-host-adoption-seams.md) |
| [0021](0021-graph-projection-in-project-library.md) | Graph projection and its field list belong in the project library | — |
| [0022](0022-plain-file-index-generations.md) | Plain-file generations; search stays available during refresh | — |
| [0023](0023-host-resolution-seams.md) | Bounded package reads, structured status, and approved Git refreshes | — |
| [0024](0024-generator-revision-and-offline-relock.md) | Pin the generator revision, bound writes, and relock offline | — |
| [0025](0025-host-adoption-seams.md) | Resolve adoption's id, share assessment, and check host files | — |
| [0026](0026-model-cache-and-source-paths.md) | Find host-installed models, collect old indexes, and align source paths | [0028](0028-model-lookup-order-correction.md) |
| [0027](0027-shared-effective-vocabulary.md) | Shared vocabulary can change findings, not inherited rule definitions | — |
| [0028](0028-model-lookup-order-correction.md) | Correct the recorded model lookup order; no runtime change | — |
| [0029](0029-profile-neutral-directory-facts.md) | Format 3 neutralizes directory facts; Profiles own placement exceptions | — |

## Retired records

Older changelogs still cite [ADR-0006](https://github.com/btwld/wayfinder/blob/4995f8d2bd9195e1239857cc8c1ab7ebb3f57da6/docs/adr/0006-raw-tier-under-references.md)
and [ADR-0007](https://github.com/btwld/wayfinder/blob/4995f8d2bd9195e1239857cc8c1ab7ebb3f57da6/docs/adr/0007-index-targets-compared-percent-decoded.md).
They remain readable at those fixed revisions, not as current guidance. The
[retirement change](https://github.com/btwld/wayfinder/commit/4ebf6a69fc8f4aafadbecbeaf455f61459ee0785)
removed them and other superseded or Profile-specific records from this catalog.
