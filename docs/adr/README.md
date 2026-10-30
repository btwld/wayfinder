# Architecture decisions

The [OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md),
[engine guide and schemas](../../implementation/README.md), then each Profile
package govern behavior. ADRs explain consequential choices; they add no rules.
Profile rationale stays in the Profile package.

Record choices likely to recur in review or costly to reverse. Normally use
100–250 words: status/date/scope, context and decision, then real consequences.
Add alternatives only when they explain the choice. Small amendments can be two
sentences in their owning topic, with a date and a link from the catalog.
Do not create records for routine file moves or reversible implementation details.

Keep existing identifiers and URLs. When behavior changes, amend the owning
record and link its replacement or amendment locally; mark reversed decisions
superseded. Git retains earlier wording. Consolidated records below are forwarding
links, not reversed decisions. Contract changes still follow the
[contributor requirements](../contributing.md#engine-contract-changes).

| Record | Decision / current home |
| --- | --- |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Preserve upstream findings and the gate grammar. |
| [0009](0009-local-knowledge-retrieval.md) | Local Arctic XS model; retrieval modes replaced by 0017. |
| [0010](0010-wayfinder-cli.md) | Explicit validate/index/search; lifecycle amended by 0022. |
| [0011](0011-wayfinder-mcp.md) | Local MCP over configured bundles; refresh reads in 0022. |
| [0012](0012-wayfinder-graph-projection.md) | Ordinary OKF graph; includes 0021's library relocation. |
| [0015](0015-profile-rule-catalogs.md) | Rules as data; generator identity from 0024; parser bounds in 0018. |
| [0016](0016-independent-profile-packages.md) | Independent Profile packages and executable conformance. |
| [0017](0017-dense-only-retrieval.md) | Dense-only retrieval as an explicit breaking simplification. |
| [0018](0018-embeddable-libraries.md) | Public libraries, host resources and locking; includes 0021/0023/0024. |
| [0019](0019-profile-aware-writes.md) | Prepare, delta assessment and guarded commit; includes 0024/0025. |
| [0020](0020-programmatic-adoption.md) | Adoption plan/apply and rollback boundaries; includes 0024/0025. |
| [0022](0022-plain-file-index-generations.md) | Immutable plain-file indexes, refresh reads and cleanup from 0026. |
| [0021](0021-graph-projection-in-project-library.md), [0023](0023-host-resolution-seams.md), [0024](0024-generator-revision-and-offline-relock.md), [0025](0025-host-adoption-seams.md), [0026](0026-model-cache-and-source-paths.md) | Consolidated amendments; links retained. |
