# Architecture decision records

ADRs preserve design rationale. The [OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md), the [engine contract](../../implementation/okf-implementation-guide.md), and each Profile package, such as [Bitwild](../../profiles/bitwild/README.md), govern current behavior in that order. Accepted decisions apply within their recorded scope. A proposed decision is not part of the engine contract or any Profile. Do not reopen an accepted decision without new evidence that defeats its rationale. Supersede it with a new ADR when the decision changes; a revision to an unpublished design must be marked and linked to its earlier text.

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
| [0004](0004-closed-concepta-profile-validator.md) | Accepted; superseded in part by 0014 for 2026.3 and, if accepted, wholly by 0016 | Closed Profile validator over independent OKF |
| [0006](0006-raw-tier-under-references.md) | Accepted; amended for 2026.3 raw-tier indexes | Optional per-source `raw/` tier for verbatim originals |
| [0007](0007-index-targets-compared-percent-decoded.md) | Accepted for 2026.2; superseded for 2026.3 by the generated-index rule | Compare index URLs after percent-decoding |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Accepted; amended, if accepted, by 0016 for the finding namespace | Preserve OKF's finding-report wire format |
| [0009](0009-local-knowledge-retrieval.md) | Accepted | Keep Arctic XS for optional embeddings; BM25 remains the library default |
| [0010](0010-wayfinder-cli.md) | Accepted; amended for 2026.3 relationships | Wayfinder CLI for validation and persistent local search |
| [0011](0011-wayfinder-mcp.md) | Accepted | Wayfinder MCP adapter over local stdio |
| [0012](0012-wayfinder-graph-projection.md) | Accepted; amended for 2026.3 relationships | Project the ordinary OKF graph, plus typed relationship edges beside it |
| [0013](0013-captures-layer-outside-the-bundle.md) | Proposed | Optional capture workflow; standardizing a source-document type remains open |
| [0014](0014-external-profile-bindings.md) | Accepted for 2026.3; superseded in part, if accepted, by 0015 for source rule catalogs and by 0016 for the base, chain wiring, and dispatch | Direct Git sources, additive vocabulary and exact-release dispatch |
| [0015](0015-profile-rule-catalogs.md) | Proposed; amended by 0016 | Evaluate Profiles as rule catalogs over parsed bundle facts |
| [0016](0016-independent-profile-packages.md) | Proposed | Every Profile is an independent package the validator enforces |
