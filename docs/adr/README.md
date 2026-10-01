# Architecture decision records

ADRs preserve design rationale; the [OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md), [current Profile](../../profile/okf-profile.md), and [implementation guide](../../implementation/okf-implementation-guide.md) govern current behavior in that order. Accepted decisions apply within their recorded scope; proposed decisions are not Profile rules. Do not reopen an accepted decision without new evidence that defeats its rationale. Supersede it with a new ADR when the decision changes; a revision to an unpublished design must be marked and linked to its earlier text.

ADRs 0004 and 0006–0013 were condensed on 2026-09-28. Their `Revised` headers
link to the text at `dfd46e1` so the later wording is not mistaken for what
was deliberated on the original decision dates. ADR-0014 records its own
pre-release design revision.

ADR filenames use the current Wayfinder product vocabulary. The [documentation
index](../index.md) points to current guides. These records govern this
repository, not ADRs inside a project's `knowledge/architecture/`.
Unsettled maintenance questions remain in the [decision queue](../decision-queue.md),
not in an accepted ADR.

## Record format

Every accepted ADR has a short metadata header with `Status`, `Date`, and
`Scope`; `Revised`, `Supersedes`, `Builds on`, and `Driver` are added when they clarify
history. The body uses `Context`, `Decision`, and `Consequences`; add
`Options considered` or `Reconsider when` only when they contain distinct,
documented evidence. A proposed ADR uses `Proposal` and
`Decision gate` instead of claiming an accepted decision. Current commands and
dependency details belong in the relevant guide; an ADR records the durable
choice and links there.

| ADR | Status | Decision |
| --- | --- | --- |
| [0004](0004-closed-concepta-profile-validator.md) | Accepted; partly superseded by 0014 and, if accepted, 0015 | Closed Profile validator over independent OKF |
| [0006](0006-raw-tier-under-references.md) | Accepted | Optional per-source `raw/` tier for verbatim originals |
| [0007](0007-index-targets-compared-percent-decoded.md) | Accepted for 2026.2; superseded for 2026.3 by Profile §9 | Compare index URLs after percent-decoding |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Accepted | Preserve OKF's finding-report wire format |
| [0009](0009-local-knowledge-retrieval.md) | Accepted | Keep Arctic XS for optional embeddings; BM25 remains the library default |
| [0010](0010-wayfinder-cli.md) | Accepted; amended for 2026.3 relationships | Wayfinder CLI for validation and persistent local search |
| [0011](0011-wayfinder-mcp.md) | Accepted | Wayfinder MCP adapter over local stdio |
| [0012](0012-wayfinder-graph-projection.md) | Accepted; amended for 2026.3 relationships | Project the ordinary OKF graph, plus typed relationship edges beside it |
| [0013](0013-captures-layer-outside-the-bundle.md) | Proposed | Optional capture workflow; standardizing a source-document type remains open |
| [0014](0014-external-profile-bindings.md) | Accepted for 2026.3 | Direct Git sources, additive vocabulary and exact-release dispatch |
| [0015](0015-profile-rule-catalogs.md) | Proposed | Evaluate Profiles as rule catalogs over parsed bundle facts |
