# Analysis

* [Engine compatibility with OKF](engine-compatibility-with-okf.md) - The four-part compatibility test and one row per engine behavior that reads, writes or reports on a bundle, redone for each OKF release.

# Architecture Decision Record

* [Expose embeddable libraries and leave resources to the host](expose-embeddable-libraries.md) - Project and retrieval behavior are public libraries with injected resources, bounded roots, typed failures and host-owned lifecycle.
* [Keep dependencies compatible with hosts](keep-dependencies-host-compatible.md) - Ack 2 and analyzer 13 are adopted for host compatibility, which moves ObjectBox to its 6 preview until the first stable 6 release.
* [Project the ordinary OKF graph](project-the-ordinary-okf-graph.md) - The graph is OKF's own, with typed relationship edges beside it, projected in the project library and never a source of truth.
* [Run explicit local operations from one CLI](run-explicit-local-operations.md) - One CLI validates, indexes and searches; no command downloads a model or rebuilds an index implicitly.
* [Serve MCP over the CLI's services](serve-mcp-over-shared-services.md) - Validate, index, search, query and graph over local MCP stdio on the CLI's own services, with no HTTP, authentication or authoring tool.

# Architecture Document

* [Entry points](entry-points.md) - Which interface serves which caller: the CLI, MCP, each public Dart library and the Flutter SDK, with the document that owns each.

# Glossary Definition

* [Engine contract](engine-contract.md) - The implementation guide and the two published JSON Schemas, ranked below OKF and above every Profile.
* [OKF Specification](okf-specification.md) - The authoritative Open Knowledge Format specification that the engine contract and every Profile build on.
