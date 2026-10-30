# ADR-0026: Find a host's model, and match source paths to the builtin

- Status: accepted; consolidated into the linked topics (editorial, no reversal)
- Date: 2026-10-24

Runtime lookup uses the installed model before the data-directory cache; generation cleanup and source paths follow the shared lifecycle.

Rationale and current boundaries: [ADR-0022](0022-plain-file-index-generations.md#cleanup-and-source-paths-0026-2026-10-24) and the [CLI runtime guide](../../packages/wayfinder_cli/README.md#embedding-model-lookup).
