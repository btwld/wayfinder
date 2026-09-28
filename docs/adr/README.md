# Architecture decision records

ADRs preserve design rationale; the [OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md), [current Profile](../../profile/okf-profile.md), and [implementation guide](../../implementation/okf-implementation-guide.md) govern current behavior in that order. Accepted decisions apply within their recorded scope; proposed decisions are not Profile rules. Supersede an accepted decision with a new ADR when its rationale no longer holds.

Historical records retain their original names and package context. The [documentation index](../index.md) points to current guides. These records govern this repository, not ADRs inside a project's `knowledge/architecture/`.

| ADR | Status | Decision |
| --- | --- | --- |
| [0004](0004-closed-concepta-profile-validator.md) | Accepted; partly superseded for 2026.3 by 0014 | Closed Profile validator over independent OKF |
| [0006](0006-raw-tier-under-references.md) | Accepted | Optional per-source `raw/` tier for verbatim originals |
| [0007](0007-index-targets-compared-percent-decoded.md) | Accepted | Compare index URLs after percent-decoding |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Accepted | Preserve OKF's finding-report wire format |
| [0009](0009-local-knowledge-retrieval.md) | Accepted | Keep Arctic XS for optional embeddings; BM25 remains the library default |
| [0010](0010-station-cli.md) | Accepted | One CLI for validation and persistent local search |
| [0011](0011-station-mcp.md) | Accepted | Serve those operations over local MCP stdio |
| [0012](0012-wayfinder-graph-projection.md) | Accepted | Project the ordinary OKF graph |
| [0013](0013-captures-layer-outside-the-bundle.md) | Proposed | Optional capture workflow; standardizing a source-document type remains open |
| [0014](0014-external-profile-bindings.md) | Accepted for 2026.3 | External project bindings with exact release dispatch |
