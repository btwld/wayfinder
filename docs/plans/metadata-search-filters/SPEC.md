---
kind: plan
date: 2026-09-30
repository: btwld/wayfinder
branch: feat/flutter-knowledge-bundle-implementation
commit: 0d7a4b8543f775059546442fe99b5958e5f33794
worktree: /Users/leofarias/Documents/Codex/2026-09-29/ca/work/wayfinder-flutter
skill: engineering-kit:writing-plans
session: null
status: draft
---

# Metadata-filtered search

## Goal

Allow callers to restrict Wayfinder search to concepts whose OKF metadata matches
explicit filters. Filtering happens before lexical or dense scoring, so an
excluded concept cannot appear as a result or re-enter through relationship
context.

The normal query remains required. A filter selects the searchable document set;
it does not make a metadata field the only text embedded or searched.

## Proposed CLI

~~~sh
wayfinder search "navigation" \
  --bundle flutter-dev-kit \
  --tag routing --tag navigation \
  --require-tag mobile --require-tag flutter \
  --type guide \
  --status stable \
  --path-prefix architecture \
  --title-contains navigation \
  --description-contains "deep links"
~~~

Tag values accept either comma-separated identifiers or repeated options:

~~~sh
--tag routing,navigation
--tag routing --tag navigation
--require-tag mobile,flutter
--require-tag mobile --require-tag flutter
~~~

The tag option matches any listed tag. The require-tag option requires every
listed tag. The same comma-separated or repeated syntax can be used with type,
status, and path-prefix. Different filter families combine with AND. Empty
filter values are rejected.

Tags, types, and statuses use exact identifiers. Title and description filters
use case-insensitive literal substring matching. They do not support regular
expressions or wildcard syntax.

## Shared input contract

Extend wayfinderSearchInput with an optional filters object:

~~~json
{
  "query": "navigation",
  "limit": 5,
  "filters": {
    "tags_any": ["routing", "navigation"],
    "tags_all": ["mobile", "flutter"],
    "types": ["guide"],
    "statuses": ["stable"],
    "path_prefixes": ["architecture"],
    "title_contains": "navigation",
    "description_contains": "deep links"
  }
}
~~~

The same contract is used by the CLI and MCP search tool. Defaults preserve
current unrestricted behavior.

## Existing architecture to extend

- KnowledgeSearchPolicy already filters by lifecycle status, concept type, and
  path prefix.
- KnowledgeIndex.search computes eligibility before loading embeddings.
- contextForMatches applies the same policy to governing and relationship
  context.
- OkfMetadata already exposes tags, title, description, and raw frontmatter.
- searchBundles uses one query vector across bundles and keeps each bundle's
  saved index.

No new vector format or embedding model is required. Metadata filters operate on
the loaded snapshot, then eligible chunk IDs are passed to the embedding store.

## Implementation sequence

### 1. Add a typed filter value

Files: packages/wayfinder_embeddings/lib/src/okf/knowledge_index.dart and
shared model files as needed.

Add an immutable filter representation with validation for empty values. Preserve
the existing status, type, and path behavior and add tags, title, and
description predicates.

### 2. Extend policy eligibility

Implement:

- any-tag matching
- all-tag matching
- repeated type/status matching
- segment-aware path prefix matching
- case-insensitive title containment
- case-insensitive description containment

Missing metadata fails only the filter that requires it. An empty filter means
unrestricted search.

### 3. Thread filters through search

Files:

- packages/wayfinder_cli/lib/src/search_input.dart
- packages/wayfinder_cli/lib/src/cli.dart
- packages/wayfinder_cli/lib/src/knowledge.dart
- packages/wayfinder_cli/lib/src/mcp_server.dart

Parse CLI flags into the shared filter object and pass it through explicit-bundle,
project-bundle, and MCP search paths. Keep the normal result shape unchanged.

### 4. Test eligibility and ranking boundaries

Add tests proving:

- filters run before BM25, dense, and hybrid retrieval;
- an excluded high-scoring concept never appears;
- a matching lower-scoring concept is still eligible;
- relationship and governing context cannot bypass filters;
- repeated values have the documented OR/AND behavior;
- title and description matching is literal and case-insensitive;
- tag identity is exact;
- path prefixes respect segment boundaries;
- invalid filters fail before opening the model or store;
- filtering causes no embedding or index writes;
- project search applies the same policy to every bundle and preserves the
  global result limit;
- explicit-path CLI and MCP produce equivalent results.

### 5. Document and evaluate

Update the CLI and MCP search documentation with the filter contract and example.
Run the existing retrieval fixture gate and Flutter bundle queries to ensure
default unrestricted search has no regression.

## Compatibility and performance

Filters do not invalidate embeddings or require reindexing. They add one metadata
eligibility pass and reduce the set of vectors loaded and scored. For the current
local bundles this is the simplest exact implementation. A separate metadata
index can be considered if profiling shows snapshot scans are material for very
large bundles.

Do not introduce field-scoped semantic search in this change. Searching only the
description or only tags would require a separate retrieval contract and
evaluation set.

## Acceptance criteria

- Existing commands with no filters behave exactly as before.
- CLI and MCP accept the same structured filter semantics.
- Filtered searches never score or return excluded concepts.
- Relationship expansion obeys the same eligibility policy.
- No reindex is required when adding or changing a filter.
- Dense, BM25, hybrid, explicit-bundle, and project-bundle paths are covered.
- Documentation and focused tests describe the semantics.
