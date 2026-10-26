# ADR-0026: Find a host's model, and match source paths to the builtin

- Status: accepted
- Date: 2026-10-24
- Scope: where the CLI finds an embedding model a host installed, when superseded index generations are deleted, and which source paths a search reports; no Profile rule
- Amends: [ADR-0010](0010-wayfinder-cli.md) and [ADR-0018](0018-embeddable-libraries.md)
- Model lookup order corrected by: [ADR-0028](0028-model-lookup-order-correction.md)

## Context

ADR-0010 and ADR-0018 stay as they were accepted. This record carries three
decisions that this release needs and that those records do not.

## Decision

- The CLI looks for the embedding model in this order: `WAYFINDER_EMBEDDING_MODEL`,
  the verified model `EmbeddingModelCache` installed in the data directory,
  then the bundle's `models/` and `./models` during development. The
  retrieval library still downloads a model only when a host calls
  `provision`, and deletes one only when a host calls `remove`.
- Every index run, including one that finds the index current, and `prune`
  delete generations superseded more than the grace period ago. A burst of
  forced indexes no longer leaves those generations until the next publish.
- A search reports a path-valued source the way `path-targets-exist` does.
  A directory counts as present. A target that starts with `/` does not
  leave the bundle, `/../` included. An `invalid` path that stays in the
  bundle is malformed, and validation reports it, so the search does not.

## Consequences

The command uses the model a host already installed. Old generations are
collected without waiting for the next publish. A search and
`path-targets-exist` agree on which source paths are missing.
