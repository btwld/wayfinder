# Architecture Decision Record

* [Bound ingestion and cite resolved sources](bound-ingestion-and-cite-resolved-sources.md) - Search Markdown shows the shared resolver's source decisions, encoder failure is attributed at its own calls, and ingestion is bounded by digests and a temporary spool.
* [Embed with a verified local model](embed-with-a-local-model.md) - Verified local Arctic Embed XS Q8_0 weights, chosen on size and cost.
* [Publish indexes as immutable plain-file generations](publish-indexes-as-immutable-generations.md) - Snapshot and vector generations with an atomically replaced pointer, readable during refresh, plus the model lookup order.
* [Query live concepts exactly](query-live-concepts-exactly.md) - Read-only structured queries in the core project library, shared by CLI and MCP, with saved query ids in `.wayfinder/queries/`.
* [Retrieve with dense search only](retrieve-with-dense-search-only.md) - Library, CLI, MCP and evaluation searches are dense, with no lexical or hybrid mode and no implicit fallback.
