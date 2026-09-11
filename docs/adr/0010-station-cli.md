# ADR-0010: Wayfinder validates, indexes and searches local knowledge

Naming update (2026-09-10): Wayfinder was developed as the Station prototype.
The ADR number and filename remain stable; current commands use Wayfinder.

- Status: accepted
- Date: 2026-09-09
- Scope: application commands and local index lifecycle; no profile rule changes
- Builds on [ADR-0009](0009-local-knowledge-retrieval.md)

## Context

The embedding library supplies retrieval and evaluation tools, while `okfp`
validates bundles. Users need one CLI accepting a bundle path and an arbitrary
query. The agreed interface is `wayfinder validate`, `wayfinder index` and
`wayfinder search`; a `profile` or `knowledge` group adds no useful choice.

The model comparison supports retaining Arctic XS. Choosing a fixed semantic
workflow for Wayfinder is a product decision, not evidence that embeddings win
every query or that similarity establishes authority or answerability.

## Decision

- Wayfinder is an application package in this workspace. The Concepta OKF
  Profile remains the standard; Wayfinder introduces no new profile declaration
  or metadata meanings.
- `validate` calls the existing validator API: upstream OKF checks, then the
  declared Concepta release. Preserve findings, exit codes and UNASSESSED
  judgment state. Existing `okfp validate` remains compatible.
- `index` always creates local embeddings with Arctic XS through llamadart.
  `search` uses saved document vectors and a temporary query vector.
  Neither exposes a mode flag. The reusable library retains its alternative
  retrieval methods and historical benchmark baselines.
- Model acquisition belongs to build tooling. Distribute the full native
  bundle with verified weights, manifest and license. Runtime indexing
  and querying do not download or train models.
- ObjectBox persists one derived index per canonical bundle path outside the
  source repository. Save original inputs, fitted passages, metadata,
  citations and graph-reconstruction inputs with the embedding configuration.
- Updates use a private generation containing a database and snapshot record.
  Close the database and flush the record before atomically replacing the
  current-generation pointer. This avoids a new ObjectBox entity schema and
  preserves the previous completed index if loading or inference fails.
- Serialize commands for the same bundle using an OS file lock before opening
  ObjectBox. Hash source content and inventory before/after operations to
  detect observed edits. Search rejects stale/incompatible indexes and tells
  the caller to run `wayfinder index`.
- Preserve all lifecycle states in the initial search scope and display status.
  Include bounded one-hop declared relationships with reasons/notices. Do not
  infer governing-source hierarchy from type, verification or similarity.

## Consequences

Fresh searches reopen the saved snapshot without document inference, token
fitting or lexical-index construction. They still read source hashes,
reconstruct the upstream OKF graph, initialize the model and encode the query.
The adapter continues exact scoring over eligible vectors.

Incremental indexing copies the closed compatible database into a staging
generation to reuse vectors. This adds disk I/O and temporarily requires room
for two databases. Successful indexing removes inactive owned generations,
including abandoned work from interrupted processes. Measure large indexes
before optimizing this initial correctness tradeoff.

Saving original inputs means a complete copy of the bundle text lives in
per-user application data on every machine that indexes it. That is the cost of
searching without re-reading and re-fitting sources; it stays on the machine and
disappears with the index directory.

Locks serialize same-bundle searches as well as indexing. Hash rechecks detect
observed changes, not every race in an adversarial filesystem. Atomic publication
protects ordinary process failures; it is not a universal power-loss protocol.

The CLI has no watcher, background service, LLM answer generation, automatic
fixes or navigation `index.md` generation. Reindex explicitly after edits.
Validation remains available when model assets are missing. Native packaging
is exercised on Linux/macOS; Windows validation is covered separately.

The [Wayfinder guide](../../packages/wayfinder/README.md) owns commands, persistence
locations and verification instructions. Existing bundles stay conformant;
this decision requires no bundle migration or profile release.
