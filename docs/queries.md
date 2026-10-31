# Structured queries and saved views

`query` selects whole OKF concepts from live files. Use it for an exact list or
count; use `search` for ranked passages relevant to a question. Queries need no
embedding model or saved index and make no update check or network request.

```sh
wayfinder query --type Guide --tag routing --output json
wayfinder query knowledge --select title,type,tags --order-by title:asc
wayfinder query --group-by type --limit 10 --output json
wayfinder query --saved routing-guides --output json
```

Without a bundle path, query uses the project's configured bundles, or its
conventional `knowledge/` folder. `--bundle <name>` narrows the project scope;
it cannot be combined with an explicit bundle path. Equal concept IDs in two
bundles remain separate records. A record's identity always includes the bundle
path, concept ID and source path; selected columns never remove that identity.

## Filters and columns

Filters use the same predicate as CLI search:

- `--type`, `--tag`, `--status` and `--path-prefix`: repeated/comma-separated
  values use OR within a field; fields combine with AND.
- `--require-tag`: every named tag must match.
- `--title-contains` and `--description-contains`: literal, case-insensitive
  substrings. Missing/non-string metadata does not match.

Identifiers are exact and case-sensitive. A path prefix denotes a concept or
directory boundary, not an arbitrary substring. No filters selects all concepts.
Reserved `index.md`/`log.md` files and binary/raw evidence assets are not rows.
Records embedded inside a concept's body do not become separate rows.

`--select` accepts `title`, `description`, `type`, `status`, `effective_status`,
`tags` and `resource`. Defaults: title, type, effective_status. Missing metadata
is null. `status` preserves the authored value; `effective_status` is `stable`
when status is absent. Producer-defined values remain intact. Query never
interprets lifecycle as task state or approval.

`--order-by field[:asc|desc]` accepts title, type, effective_status, id and path.
It is repeatable. String comparisons use Dart's locale-independent `compareTo`
(UTF-16 code-unit ordering); missing/non-string values sort last in either
direction. Bundle path and concept ID ascending break ties. With no order,
bundle path and ID determine the order.

## Completeness, pagination and grouping

`--offset` defaults to zero; `--limit` defaults to 100 and accepts 1–1000.
Filtering and sorting operate on every matching concept before pagination.
JSON has `schema_version: "1"`, `kind: "rows"`, normalized `query`, selected
`bundles`, `total`, `offset`, `returned`, `has_more` and `rows`. Each row has
`bundle`, `id`, `path` and selected `values`. Empty results succeed. Read
`has_more` before treating a page as the complete collection.

`--group-by type` or `--group-by effective_status` produces `kind: "groups"`,
`groups` of `{key, count}`, and `group_total`. `total` still counts matching
concepts before pagination. Grouping processes all matching rows, then paginates
the groups; it cannot be combined with select/order-by. Group keys sort
ascending, with null last for missing/non-string values. Tag grouping, joins,
custom expressions and arbitrary field predicates are not supported.

Only selected values on the returned page are converted to JSON. Each page is bounded to 100,000 expanded values, 64 nested levels and 4 Mi UTF-16 code units of strings (keys included); exceeding that fails with `query-metadata-limit`. Non-string map keys and nonfinite numbers in selected values fail with `query-metadata-invalid`, rather than losing or coercing source data. Unselected extension metadata is not expanded.

Queries reread source files on every call. Malformed or nonconformant OKF refuses
the whole operation, including every selected bundle; Profile assessment is
separate. Files are fingerprinted before and after reading; an observed change
raises `query-source-changed` and should be retried. This is not an atomic
filesystem snapshot and cannot detect every concurrent edit/revert. Read claims honor an existing okf `.okf.lock`; they create no lock file.
Concepts, indexes, logs and assets are unchanged.

CLI exit status is 0 on success (zero matches included), 1 when OKF findings
refuse a query, and 2 for input, I/O or cancellation errors. JSON refusals contain
`error: "query-refused"` and the OKF `report`; other failures use the existing
CLI diagnostic envelope. MCP failures have `isError: true`; empty output does not.

## Save a query

Create a tracked project file `.wayfinder/queries/routing-guides.json` outside
the OKF bundle:

```json
{
  "format": 1,
  "where": {"types": ["Guide"], "tags": ["routing"]},
  "select": ["title", "type", "tags"],
  "order_by": [{"field": "title", "direction": "asc"}]
}
```

Its filename is its ID. IDs contain lowercase letters/digits separated by single
hyphens, at most 64 characters. Definitions are at most 64 KiB, use integer
format 1, and reject duplicate/unknown keys and unsupported versions. No remote
references, includes, executable content or bundle roots are accepted. Canonical
paths must stay within the project's query directory. As with live bundle I/O,
path checks assume no adversarial concurrent filesystem replacement.

Saved `where` keys are types, tags, required_tags, statuses, path_prefixes,
title_contains and description_contains. Optional select/order_by/group_by have
the same semantics as inline queries. Runtime offset/limit are allowed; combining
a saved ID with inline filters/columns/ordering/grouping is an error.

Saved definitions require a consuming project containing the selected bundle.
Standalone external bundle queries remain available inline. This is a Wayfinder
consumer convention, not a new OKF field or Profile requirement. No Profile,
configuration, lock or index migration is required.

## MCP and Dart

MCP `query` accepts exactly one of `query` or `saved`, plus optional integer
offset/limit. Example arguments:

```json
{"query": {"where": {"types": ["Guide"]}}, "limit": 20}
```

```json
{"saved": "routing-guides", "offset": 0, "limit": 20}
```

It uses the server's startup/project scope and accepts no per-call filesystem
root. Results match CLI JSON. Tool discovery marks it read-only and idempotent.
Restart the MCP host after upgrading to discover the added tool.

Dart hosts import `package:wayfinder/project.dart`, build a
`WayfinderQuery.fromJson`, select bundles with
`discoverWayfinderQueryBundles` (or existing `WayfinderProject` discovery), and
call `queryWayfinderBundles`. `loadWayfinderSavedQuery` resolves a saved ID in
that consuming project. Results provide `toJson()` and `toText()`. Hosts can
pass a `WayfinderCancellation`. Core has no dependency on embeddings; the
existing `KnowledgeMetadataFilter` imports through embeddings remain supported.

## Computations and rendered views

An application can render query results as a table or another derived view.
Source concepts retain their editable authority; rendered output is a snapshot.
The query engine does not execute `Attested Computation` code, render document
links automatically, synchronize Notion or establish execution attestation.
A future executor/receipt/attester integration needs an explicit contract.
