# Documentation index

## Vocabulary

[Glossary](GLOSSARY.md) — Canonical language for the Profile, automated validation, contextual review, review reports, and complete assessment.

## Compatibility

[Compatibility review](compatibility-review.md) — Rule-level evidence that Concepta Profile 2026.1 preserves pinned OKF 0.2.

[Assessment coverage](../implementation/profile-coverage.md) — Assignment of Profile rules to automated validation or contextual review; separate from compatibility evidence.

## Maintenance

[ObjectBox configuration and build review](objectbox-build-review.md) — Runtime/generator pins, native assets, schema compatibility and platform evidence.

[Wayfinder retrieval](wayfinder_embeddings.md) — Library setup, evaluation and implementation evidence.

[Wayfinder naming and release plan](wayfinder-release-plan.md) — Product names, package boundaries, migration, and publication sequence.

[Repository maintenance review](maintenance-review.md) — Responsibilities to retain, housekeeping corrections, existing follow-up issues, and the second-brain workflow to explore. Reviewed 2026-09-09; linked issues own current work status.

[Skill evaluation](skill-evaluation.md) — Synthetic execution cases, corrections, validation evidence, and limits for the distributed skills.

## Operations

[Install Wayfinder](install.md) — Native installation without Dart, plugin setup and migration, usage, upgrades and troubleshooting.

[Release Wayfinder](releasing.md) — Package tags, pub.dev OIDC, verified native bundles and cli_pkg/Grinder tasks.

## ADRs

[0004: Closed Concepta Profile validator](adr/0004-closed-concepta-profile-validator.md) — Accepted. Closed validation, contextual review, registries, authored logs, and derived indexes.

[0006: Raw tier under references](adr/0006-raw-tier-under-references.md) — Accepted. Optional per-source storage for verbatim originals; each directory's index is the only Markdown inside the tier.

[0007: Percent-decoded index targets](adr/0007-index-targets-compared-percent-decoded.md) — Accepted. Compare relative URLs after decoding so real-world filenames stay expressible.

[0008: OKF finding contract](adr/0008-okfp-adopts-okf-finding-contract.md) — Accepted. Reuse OKF's finding report as the wire format and retire the separate load-issue channel.

[0009: Local knowledge retrieval](adr/0009-local-knowledge-retrieval.md) — Accepted. Keep Arctic XS for optional local embeddings; retain BM25 by default.

[0010: Wayfinder CLI](adr/0010-station-cli.md) — Accepted. Wayfinder validates, indexes and searches with local embeddings and persistent bundle snapshots.

[0011: Wayfinder MCP](adr/0011-station-mcp.md) — Accepted. Serve Wayfinder tools over local MCP stdio.

[0012: Wayfinder graph projection](adr/0012-wayfinder-graph-projection.md) — Accepted. Project the ordinary OKF graph; mermaid and DOT are text for an external preview.
