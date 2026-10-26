# ADR-0028: Correct the recorded model lookup order

- Status: accepted
- Date: 2026-10-26
- Scope: factual correction to the CLI model lookup record; no runtime change
- Amends: [ADR-0026](0026-model-cache-and-source-paths.md)

## Context

ADR-0026 puts the verified data-directory model before bundled and development
models. The implementation, CLI README, changelog, and `model_location_test`
instead agree that installed and development locations take precedence over
the cache. A valid cache alone works; an invalid higher-priority bundled
model is reported rather than skipped. The audit reproduced both cases.

## Decision

Keep that tested behavior. The order is `WAYFINDER_EMBEDDING_MODEL`, the
installed bundle's `models/`, `./models`, the source package's model during
development, then the verified model `EmbeddingModelCache` installed in the
data directory. This record corrects ADR-0026's order; it does not reorder
lookup or add automatic provisioning.

## Consequences

No migration or package format change is needed. A host's verified cache is
used when no higher-priority model is present. The existing error reporting
for invalid higher-priority models is unchanged.
