# Wayfinder operations

## Choose the interface

Prefer Wayfinder MCP `search`, `index`, `validate`, `graph` tools (usually
`mcp__wayfinder__` or `mcp__plugin_wayfinder_wayfinder__`). Default launches discover
configured `applies_to` bundles or `knowledge/`; explicit launch paths or
`WAYFINDER_KNOWLEDGE_DIR` select one with single-bundle result shapes.
Search takes `{"query": "<question>", "limit": 5}`, uses a local encoder and a
global limit; no bundle list or retired `mode` field. Index refreshes selected
bundles. Project validation/graph return independent `bundles` with name/path;
check every gate/exit code. Graph returns OKF JSON plus typed `field_edges` and
accepts `types`, `path_prefixes`, `resolutions` filters.

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
and retry. While another Wayfinder command indexes a bundle, search (CLI or MCP)
instead returns that bundle's last completed index with a `refresh-in-progress`
notice. Passages from files edited since are marked `source changed` (JSON
`"sourceChanged": true`) and named in a `source-changed` notice: read those
files directly before citing them, or search again once the index finishes.
Explicit paths preserve the single-bundle JSON shape. Do not combine a path and
`--bundle`.

For **graph**, `--type`, `--path-prefix` and `--resolution` are repeatable and match the MCP
`types`, `path_prefixes` and `resolutions` filters.

Use CLI `--output=json` for programmatic results. MCP returns JSON for
`validate`, `index`, and `graph`, and Markdown for `search`. If neither the tools nor the
`wayfinder` command exist, say so and see [Troubleshooting](#troubleshooting)
rather than silently falling back to grep-only answers.

## Validate

Run validation before saying a bundle conforms, and after editing one.
`validate` reads only a current lock/cache: it never fetches or writes.
`--fix` is the one exception to read-only validation. When a rule in the
selected chain uses `matches-generated`, it first writes okf's generated
indexes, then validates. Otherwise it writes nothing and reports
`wayfinder/fix-not-applied`, as it does for a bundle with no selected
Profile or one OKF rejects. A fix that writes takes okf's bundle lock and
leaves `.okf.lock` at the bundle root; it is not knowledge, so keep it out of
commits and expect the project's `.gitignore` to list it. A bundle with no `wayfinder.json` above it
reports `wayfinder/config-missing`. A missing or stale lock still leaves an
independent OKF result; run `wayfinder get` to resolve the declared source, or
`wayfinder upgrade` only when intentionally advancing a mutable ref.
`graph`, `index`, and `search` do not need Profile-source resolution.

The gate combines OKF, Profile findings and run diagnostics (`wayfinder/` IDs).

| Exit / Gate | Meaning / report |
| --- | --- |
| 0 / PASS | OKF passed, every selected rule ran, no error finding. Advisories, summary notes and note/warning diagnostics remain information; mention relevant ones without calling them failures. |
| 1 / FAIL | OKF or a Profile rule failed. Report each error's id, path and message. |
| 2 / INCOMPLETE | Not everything was assessed. Name the diagnostic and remedy, e.g. `profile-unresolved` needs `get`; do not claim a pass. Stopped JSON runs still report `wayfinder/internal-error`. |

Read `profile.summary`/text `Summary:` for permitted cases, and JSON `diagnostics`
or text `Diagnostics:` for run problems, not bundle findings.

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
| `Index is busy` | Another Wayfinder command is indexing this bundle or deleting its index. Search still works meanwhile; retry the index after it finishes. |
| `The index is being built` | The bundle's first index, or one replacing an unusable index, is still running. Retry the search after it finishes. |
| `refresh-in-progress` / `source-changed` notices | Results come from the last completed index while another command indexes. Verify passages marked `source changed` against their files. |
| `Another wayfinder get is changing <project>` | A second `get` or `upgrade` ran while one was resolving the project. Retry after it finishes. |
| `wayfinder/profile-unresolved`: a package `has no package file in the local cache` | The cache keeps each locked package file for validation, and `validate` restores one from the cached source when it can. Run `wayfinder get`; it fetches nothing while the cached source holds the locked commit. |
| `wayfinder/profile-timeout`, or `get` failing with `did not finish within 10 seconds` | Reading a package of the chain ran its rule tests past the engine's bound, as a `pattern` that backtracks without end can. No rule ran. Report it to the Profile's author; retrying does not help. |
| Embedding model missing, unreadable or failing verification | The message lists each location searched, in order, and whether `WAYFINDER_EMBEDDING_MODEL` is set; check those paths and assets. Reinstall the complete runtime when incomplete; copying only the executable is insufficient. Reindexing alone cannot repair a model-load failure. |
| Dense search reports missing compatible passage vectors | Repair the encoder if needed, then index the same bundle and retry. There is no alternate retrieval fallback. |
| CLI `--mode` or MCP `mode` rejected after upgrade | Remove the retired field, including an explicit dense value. Refresh MCP tool discovery. |
| `Wayfinder data must be outside the knowledge bundle` | `WAYFINDER_DATA_DIR` points inside the bundle. Point it elsewhere. |
