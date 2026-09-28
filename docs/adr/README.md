# Architecture decision records

ADRs preserve design rationale; the [OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md), [current Profile](../../profile/okf-profile.md), and [implementation guide](../../implementation/okf-implementation-guide.md) govern current behavior in that order. Accepted decisions apply within their recorded scope; proposed decisions are not Profile rules. Supersede an accepted decision with a new ADR when its rationale no longer holds.

Current ADR filenames use the Wayfinder product vocabulary. The former
`station-*` paths remain as short compatibility records so historical links
continue to resolve; they are not separate decisions. The [documentation
index](../index.md) points to current guides. These records
govern this repository, not ADRs inside a project's `knowledge/architecture/`.

## Record format

Every accepted ADR has a short metadata header with `Status`, `Date`, and
`Scope`; `Supersedes`, `Builds on`, and `Driver` are added when they clarify
history. The body uses `Context`, `Decision`, `Options considered`,
`Consequences`, and `Reconsider when`. A proposed ADR uses `Proposal` and
`Decision gate` instead of claiming an accepted decision. Current commands and
dependency details belong in the relevant guide; an ADR records the durable
choice and links there.

| ADR | Status | Decision |
| --- | --- | --- |
| [0004](0004-closed-concepta-profile-validator.md) | Accepted; partly superseded for 2026.3 by 0014 | Closed Profile validator over independent OKF |
| [0006](0006-raw-tier-under-references.md) | Accepted | Optional per-source `raw/` tier for verbatim originals |
| [0007](0007-index-targets-compared-percent-decoded.md) | Accepted | Compare index URLs after percent-decoding |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Accepted | Preserve OKF's finding-report wire format |
| [0009](0009-local-knowledge-retrieval.md) | Accepted | Keep Arctic XS for optional embeddings; BM25 remains the library default |
| [0010](0010-wayfinder-cli.md) | Accepted | Wayfinder CLI for validation and persistent local search |
| [0011](0011-wayfinder-mcp.md) | Accepted | Wayfinder MCP adapter over local stdio |
| [0012](0012-wayfinder-graph-projection.md) | Accepted | Project the ordinary OKF graph |
| [0013](0013-captures-layer-outside-the-bundle.md) | Proposed | Optional capture workflow; standardizing a source-document type remains open |
| [0014](0014-external-profile-bindings.md) | Accepted for 2026.3 | External project bindings with exact release dispatch |

## Why the decisions stay separate

- ADR-0004 and ADR-0014 separate the closed validator boundary from the
  2026.3 project-binding migration; 0014 supersedes only the old in-bundle
  selector and registries.
- ADR-0006 and ADR-0007 address different Profile mechanics: where verbatim
  assets live, and how index URLs are compared. They have different rules,
  findings, and migration edge cases.
- ADR-0009 through ADR-0012 cover model selection, application/index
  lifecycle, MCP transport, and graph projection. They can evolve and be
  tested independently, so combining them would hide their contracts rather
  than remove duplication.
- ADR-0013 is a proposed evidence workflow, not an accepted Profile rule.
  The historical naming/release record lives separately in
  `docs/wayfinder-release-plan.md` because it records a product migration,
  not an architecture contract.
