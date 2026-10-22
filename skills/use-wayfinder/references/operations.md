# Wayfinder operations

## Choose the interface

Check for the **Wayfinder MCP tools** (`search`, `index`, `validate`, `graph`,
usually prefixed `mcp__wayfinder__` or `mcp__plugin_wayfinder_wayfinder__`) and
prefer them. Default `wayfinder mcp` launches discover every bundle in the
nearest `wayfinder.json` (`applies_to`), or the conventional `knowledge/` fallback.
`search` takes `{"query": "<one natural-language question>", "limit": 5}`. It uses
dense retrieval across those bundles with one global limit; it needs no bundle list.
Every actual search requires the local encoder. Do not send retired `mode` fields;
unsupported fields are rejected. `index` refreshes them all. Project `validate`
and `graph` return independent reports in `bundles`, each with `name` and
project-relative `path`; read every validation report's gate and `exit_code` before
claiming the project passes. An explicit `wayfinder mcp <bundle>` launch or
`WAYFINDER_KNOWLEDGE_DIR` restricts the tools to one bundle and preserves the
single-bundle result shapes. `graph` takes optional `types`, `path_prefixes` and
`resolutions` and returns the versioned OKF graph JSON, plus a `field_edges` array
holding each concept's typed `relationships` entries.

Otherwise use the **CLI**. Search/index default to all project bundles listed by
the nearest `wayfinder.json`, or conventional `knowledge/` without configuration.
Use `--bundle <folder-name>` to filter; explicit paths still select one bundle:

```sh
wayfinder validate <bundle> [--config=wayfinder.json] [--fix] [--output=json|sarif]
wayfinder graph <bundle> [--output=json|mermaid|dot] [--type TYPE] [--path-prefix PREFIX] [--resolution STATE]
wayfinder index [<bundle>] [--bundle NAME] [--output=json]
wayfinder search [<bundle>] "<one quoted query>" [--bundle NAME] [--limit N] [--output=json]
```

Project search (CLI or MCP) ranks across selected bundles with a global limit.
Its JSON adds `bundles` and annotates each match/context hit with `bundle` and
`bundlePath`; combine that path with `chunk.sourcePath` for project-relative
citations. A stale selected index fails the whole search: run `wayfinder index`
and retry. Explicit paths preserve the single-bundle JSON shape. Do not combine
a path and `--bundle`.

For **graph**, `--type`, `--path-prefix` and `--resolution` are repeatable and match the MCP
`types`, `path_prefixes` and `resolutions` filters.

Use `--output=json` when you will parse results; explicit-path output has the
same shape a single-bundle MCP launch returns. If neither the tools nor the
`wayfinder` command exist, say so and see [Troubleshooting](#troubleshooting)
rather than silently falling back to grep-only answers.

## Validate

Run validation before saying a bundle conforms, and after editing one.
`validate` reads only a current lock/cache: it never fetches or writes.
`--fix` is the one exception to read-only validation. When a rule in the
selected chain uses `matches-generated`, it first writes okf's generated
indexes, then validates. Otherwise it writes nothing and reports
`wayfinder/fix-not-applied`, as it does for a bundle with no selected
Profile or one OKF rejects. A bundle with no `wayfinder.json` above it
reports `wayfinder/config-missing`. A missing or stale lock still leaves an
independent OKF result; run `wayfinder get` to resolve the declared source, or
`wayfinder upgrade` only when intentionally advancing a mutable ref.
`graph`, `index`, and `search` do not need Profile-source resolution.

The result ends with one gate, derived from three parts: the OKF result, the
Profile findings, and the engine's diagnostics (`diagnostics` in JSON, the
text `Diagnostics:` block). A diagnostic has a `wayfinder/` id and reports on
the run, not on the bundle.

- Exit `0` and gate `PASS`: OKF passed, no finding is an error, and every
  selected rule ran. Advisory findings may remain; mention the relevant ones
  without treating them as failures. Summary entries (`profile.summary`, or
  the text `Summary:` block) report what the Profile permits, such as a
  planned link. Note and warning diagnostics, such as
  `wayfinder/project-type`, are information too. None of these are failures.
- Exit `1` and gate `FAIL`: OKF failed or a Profile finding is an error.
  Report each error with its `id`, path and message.
- Exit `2` and gate `INCOMPLETE`: the run could not assess everything, so it
  is not a pass. An error diagnostic names why, for example
  `wayfinder/profile-unresolved` (run `wayfinder get`),
  `wayfinder/config-missing`, or `wayfinder/link-graph-unavailable`. Report
  the diagnostic, not a verdict. With `--output json` a run that stopped
  still prints a result carrying `wayfinder/internal-error`.

Validation covers only the deterministic rules; contextual judgment
is a separate review. Route by task:

| Need | Use |
| --- | --- |
| Fix findings or write any file under the bundle | [author-knowledge-bundle](../../author-knowledge-bundle/SKILL.md) |
| Whole-bundle audit with a Profile Review Report | [assess-knowledge-bundle](../../assess-knowledge-bundle/SKILL.md) |
| Seed a bundle in a repository that has none | [adopt-knowledge-bundle](../../adopt-knowledge-bundle/SKILL.md) |

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `wayfinder` not found; MCP server missing from `/mcp` | Not installed or not on the `PATH` the agent was launched with. Install the complete runtime (see the Wayfinder install guide), or set `WAYFINDER_EXECUTABLE` for the plugin. `wayfinder setup` adds the server to a project's `.mcp.json`. Restart the client after installing. |
| Wayfinder reports a newer release | `wayfinder update` upgrades the runtime and refreshes these skills. |
| Tools search only one bundle | Unset `WAYFINDER_KNOWLEDGE_DIR` and launch `wayfinder mcp` from the project. For an existing `.mcp.json`, run `wayfinder setup --force` and restart the host. Explicit bundle launches intentionally search only that bundle. |
| No project bundles found | Start the host from the consuming project and check `wayfinder.json`'s `applies_to` paths, or the conventional `knowledge/` directory. Discovery never fetches bundles. |
| `Index is missing` / `Index is stale` / `Saved index is incomplete or incompatible` / `The saved index has another configuration` / `Index belongs to another bundle` / `Embedding configuration changed` (each ends `Run wayfinder index <bundle>.`) | Run `index` on the same bundle, then search again. The first `index` after upgrading from Wayfinder 0.2 rebuilds every bundle. |
| `Knowledge changed while indexing` / `during search` | Files changed mid-command. Let edits finish and rerun. |
| `Index is busy` | Another Wayfinder command holds this bundle. Retry after it finishes. |
| `Another wayfinder get is changing <project>` | A second `get` or `upgrade` ran while one was resolving the project. Retry after it finishes. |
| `wayfinder/profile-unresolved`: a package `has no package file in the local cache` | The cache keeps each locked package file for validation, and `validate` restores one from the cached source when it can. Run `wayfinder get`; it fetches nothing while the cached source holds the locked commit. |
| Embedding model or ObjectBox library missing or unreadable | Check the reported configured path and assets. Reinstall the complete runtime when incomplete; copying only the executable is insufficient. Reindexing alone cannot repair a model-load failure. |
| Dense search reports missing compatible passage vectors | Repair the encoder if needed, then index the same bundle and retry. There is no alternate retrieval fallback. |
| CLI `--mode` or MCP `mode` rejected after upgrade | Remove the retired field, including an explicit dense value. Refresh MCP tool discovery. |
| `Wayfinder data must be outside the knowledge bundle` | `WAYFINDER_DATA_DIR` points inside the bundle. Point it elsewhere. |
