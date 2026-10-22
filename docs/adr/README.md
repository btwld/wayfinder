# Architecture decision records

ADRs record why the engine and its tools are shaped the way they are. The
[OKF specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md),
the [engine contract](../../implementation/okf-implementation-guide.md), and
each Profile package govern behavior, in that order. An ADR explains a
decision; it adds no requirement. These records govern this repository, not
ADRs inside a project's knowledge bundle.

Each record states the decision as it stands. When a decision changes, edit
its record or replace it; Git history and the guide's §9 change record keep
what came before. A Profile's own rationale lives in its package, such as the
[Bitwild README](../../profiles/bitwild/README.md).

## Record format

A short header with `Status`, `Date`, and `Scope`, plus `Updated` with the
date and a few words when the decision changed after it, then `Context`, `Decision`,
and `Consequences`. Add `Options considered` or `Reconsider when` only when
they carry distinct evidence. Commands and dependency details belong in the
relevant guide; an ADR records the durable choice and links there.

| ADR | Decision |
| --- | --- |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Publish okf's finding report unchanged and speak its grammar for Profile findings |
| [0009](0009-local-knowledge-retrieval.md) | Arctic Embed XS for local embeddings; retrieval defaults superseded by ADR-0017 |
| [0010](0010-wayfinder-cli.md) | One CLI validates, indexes, and searches local knowledge; indexes are immutable plain-file generations that searches read while an index runs |
| [0011](0011-wayfinder-mcp.md) | Serve Wayfinder tools over local MCP stdio, across the project's bundles |
| [0012](0012-wayfinder-graph-projection.md) | Project the ordinary OKF graph, with typed relationship edges beside it |
| [0015](0015-profile-rule-catalogs.md) | Profile rules are data: schemas over parsed facts, or named builtins |
| [0016](0016-independent-profile-packages.md) | Every Profile is an independent package the validator enforces |
| [0017](0017-dense-only-retrieval.md) | Dense-only retrieval; preserve model, storage, context, and generic reranking |
| [0018](0018-embeddable-libraries.md) | Public project and knowledge store libraries; the host injects resources, model, native libraries and its process layer, and its root bounds the project; bounded package reads; skill reads bounded in bytes and kept to the paths they checked; `flock` lock files; one isolate for okf bundle I/O |
| [0019](0019-profile-aware-writes.md) | One write path through okf's projection seam: rewrite only indexes whose generated text changes, caller-authored log entries, an in-memory delta gate a host may run on another isolate |
| [0020](0020-programmatic-adoption.md) | Adoption is a plan, then an apply that writes only Wayfinder's files, or nothing |
