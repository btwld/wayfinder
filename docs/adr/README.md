# Architecture decision records

ADRs record why the engine and its tools are shaped the way they are. The
[OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md),
the [engine contract](../../implementation/okf-implementation-guide.md), and
each Profile package govern behavior, in that order. An ADR explains a
decision; it adds no requirement. These records govern this repository, not
ADRs inside a project's knowledge bundle.

Each record states the decision as it was accepted. A later change is a new
record with `Amends:` or `Supersedes:` pointing at that record. Git history
and the guide's §9 change record keep what came before. A Profile's own
rationale lives in its package, such as the
[Bitwild README](../../profiles/bitwild/README.md).

## Record format

A short header with `Status`, `Date`, and `Scope`. A record that changes an
accepted one also has `Amends:` or `Supersedes:`. Then `Context`, `Decision`,
and `Consequences`. Add `Options considered` or `Reconsider when` only when
they carry distinct evidence. Commands and dependency details belong in the
relevant guide; an ADR records the durable choice and links there.

| ADR | Decision |
| --- | --- |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Publish okf's finding report unchanged and speak its grammar for Profile findings |
| [0009](0009-local-knowledge-retrieval.md) | Arctic Embed XS for local embeddings; retrieval defaults superseded by ADR-0017 |
| [0010](0010-wayfinder-cli.md) | One CLI validates, indexes, and searches local knowledge; index storage and refresh reads amended by ADR-0022; model lookup and source paths amended by ADR-0026 |
| [0011](0011-wayfinder-mcp.md) | Serve Wayfinder tools over local MCP stdio, across the project's bundles; search during an index amended by ADR-0022 |
| [0012](0012-wayfinder-graph-projection.md) | Project the ordinary OKF graph, with typed relationship edges beside it; field list and library home amended by ADR-0021 |
| [0015](0015-profile-rule-catalogs.md) | Profile rules are data: schemas over parsed facts, or named builtins; package reads bounded by ADR-0023; generator revision amended by ADR-0024 |
| [0016](0016-independent-profile-packages.md) | Every Profile is an independent package the validator enforces |
| [0017](0017-dense-only-retrieval.md) | Dense-only retrieval; preserve model, storage, context, and generic reranking |
| [0018](0018-embeddable-libraries.md) | Public project and retrieval libraries; the host injects resources and its root bounds the project; `flock` lock files; one isolate for okf bundle I/O; knowledge store amended by ADR-0022; host seams amended by ADR-0023; a write's project root amended by ADR-0024; a host's installed model amended by ADR-0026 |
| [0019](0019-profile-aware-writes.md) | One write path through okf's projection seam: rewrite only indexes whose generated text changes, caller-authored log entries, an in-memory delta gate a host may run on another isolate, and stale plans refused by the project files their selection came from; an empty diff and an unreadable project file amended by ADR-0024; the shared assessor amended by ADR-0025 |
| [0020](0020-programmatic-adoption.md) | Adoption is a plan, then an apply that writes only Wayfinder's files, or nothing; offline relock amended by ADR-0024; host adoption seams amended by ADR-0025 |
| [0021](0021-graph-projection-in-project-library.md) | The graph projection and `wayfinderLinkFields` live in the project library; graph output is unchanged |
| [0022](0022-plain-file-index-generations.md) | Plain-file index generations that search reads while an index runs; the knowledge store is the public lifecycle |
| [0023](0023-host-resolution-seams.md) | Bounded package reads, Profile status as data, and Git refreshes that name origin |
| [0024](0024-generator-revision-and-offline-relock.md) | `matches-generated` pins okf's generator revision; a write takes the host's project root; `wayfinder.json` relocks offline; an empty diff takes the lock, and an unreadable project file is `write-failed` |
| [0025](0025-host-adoption-seams.md) | Adoption binds the package's own id, shares the write assessor, and checks a host's files before it writes |
| [0026](0026-model-cache-and-source-paths.md) | The CLI finds a host's installed model; superseded generations are collected on every index; source paths match `path-targets-exist` |
| [0027](0027-shared-effective-vocabulary.md) | Every rule uses the whole chain's and project's vocabulary; inherited definitions stay unchanged, but their results can change |
| [0028](0028-model-lookup-order-correction.md) | Correct ADR-0026's lookup order to the tested behavior: installed and development models precede the verified data-directory cache |
| [0029](0029-profile-neutral-directory-facts.md) | Format 3 makes sibling-directory facts neutral; each Profile owns placement exceptions, and format 2 is explicitly unsupported |
