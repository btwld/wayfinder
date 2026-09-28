# Documentation index

## Vocabulary

[Glossary](GLOSSARY.md) — Canonical language for the Profile, automated validation, contextual review, review reports, and complete assessment.

## Compatibility

[Compatibility review](compatibility-review.md) — Rule-level evidence that Bitwild Profile 2026.3 preserves pinned OKF 0.2.

[Assessment coverage](../implementation/profile-coverage.md) — Assignment of Profile rules to automated validation or contextual review; separate from compatibility evidence.

Earlier-release evidence is preserved in the [2026.2 compatibility review](compatibility-review-2026.2.md) and [2026.2 assessment coverage](../implementation/profile-coverage-2026.2.md). These are different checks, not duplicate reports.

## Guides and engineering evidence

[ObjectBox configuration and build review](objectbox-build-review.md) — Runtime/generator pins, native assets, schema compatibility and platform evidence.

[Wayfinder retrieval](wayfinder_embeddings.md) — Library setup, evaluation and implementation evidence.

[Wayfinder project configuration](wayfinder-configuration.md) — Implemented `wayfinder.json` and installed Profile manifest schemas, binding rules, and validation order.

[Wayfinder Profile guide](wayfinder-profile-guide.html) — Visual summary of AGENTS.md, Profiles, project bindings, tags, status, and validation coverage.

[Skill evaluation](skill-evaluation.md) — Synthetic execution cases, corrections, validation evidence, and limits for the distributed skills.

## Operations

[Install Wayfinder](install.md) — Native installation without Dart, plugin setup and migration, usage, upgrades and troubleshooting.

[Release Wayfinder](releasing.md) — Package tags, pub.dev OIDC, verified native bundles and cli_pkg/Grinder tasks.

## Decisions and historical records

[ADR catalog](adr/README.md) — The single list of accepted, superseded-in-part, and proposed decisions. Read each record in its stated release and historical context; a proposed ADR is not a current Profile rule.

[Wayfinder naming and release plan](wayfinder-release-plan.md) — Historical 2026-09-10 rename and publication record, not current installation or release instructions.
