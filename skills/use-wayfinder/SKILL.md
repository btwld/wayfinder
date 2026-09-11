---
name: use-wayfinder
description: Search, index, validate, and project the relationship graph of a project's OKF knowledge bundle with Wayfinder, through its MCP tools or the wayfinder CLI. Use whenever a question may be answered by the project's recorded knowledge — decisions, requirements, conventions, ownership, rationale, prior analysis — before answering from memory or grepping; whenever a bundle changed and search must see it; before claiming a bundle passes validation; and when you need the ordinary OKF concept graph.
---

# Using Wayfinder

Wayfinder is a local tool for an Open Knowledge Format (OKF) knowledge bundle,
usually `knowledge/` in the project root. It does four things: **validate** the
bundle against OKF and its declared Concepta Profile release, **index** it into
saved local embeddings, **search** that index for cited passages, and **graph**
the ordinary OKF relationship graph. Nothing is sent off the machine, and
indexing writes only derived data outside the bundle. Graph is a live
projection, not a source of truth; Mermaid and DOT are text for an external
preview.

Its value is grounding: an answer built from cited passages of the project's own
recorded decisions beats one built from general knowledge or a keyword grep that
misses paraphrases. So when a question touches what the project decided, requires,
owns, or learned, search first and answer from what you find.

## Choose an interface

Prefer the **Wayfinder MCP tools** when they are available (the `wayfinder`
plugin registers them as `validate`, `index`, `search` and `graph`). They are bound to one
bundle — `knowledge/` by default, or `WAYFINDER_KNOWLEDGE_DIR` — so they take no
path. `search` takes `query` and an optional `limit` (1–100, default 5).
`graph` takes optional `types`, `path_prefixes` and `resolutions` and returns
the versioned OKF graph JSON.

Otherwise use the **CLI**, which takes an explicit bundle path:

```sh
wayfinder validate <bundle> [--output=json]
wayfinder graph <bundle> [--output=json|mermaid|dot]
wayfinder index <bundle> [--output=json]
wayfinder search <bundle> "<one quoted query>" [--limit N] [--output=json]
```

Use `--output=json` when you will parse results; it is the same shape the MCP
tools return. If neither the tools nor the `wayfinder` command exist, say so and
see [Troubleshooting](#troubleshooting) rather than silently falling back to
grep-only answers.

## Search, then verify

1. **Search with the question's meaning**, not just its keywords. Retrieval is
   semantic, so a natural-language query finds paraphrases. Run a second query
   with different wording if the first misses an obvious angle.
2. **If search says the index is missing, stale or incompatible, index and search
   again.** Search refuses to read an index that no longer matches the bundle's
   files, so this is expected after any edit, on first use, or after an upgrade.
   Indexing is incremental — unchanged passages are reused, and a bundle that
   already matches its index returns at once — but the first run on a bundle can
   take a minute or more. Do not pre-emptively re-index when search works. If
   results look wrong for an unchanged bundle, `wayfinder index <bundle> --force`
   rebuilds the index from scratch.
3. **Read the results.** JSON output has three parts:
   - `context` — the ranked, bounded passages to use. Each has `chunk.sourcePath`
     (relative to the bundle), `chunk.lineStart`–`chunk.lineEnd`,
     `chunk.content`, and `chunk.metadata.okf.frontmatter` (including `status`),
     plus a `reason`: `match` (direct hit), `relationship` (reached through a
     labelled link from a match — `viaPath` names that match), or `governing`
     (a governing source pulled in ahead of the passage it governs).
   - `matches` — the raw similarity hits behind `context`.
   - `notices` — gaps worth reporting, such as an unresolved relationship link.
   Text output prints the same passages as `path:start-end [status; reason]`.
4. **Verify before answering.** Ranking is similarity, not truth: open the cited
   file at those lines and confirm it actually supports your claim. Cite as
   `knowledge/<sourcePath>:<start>-<end>` (the path as seen from the project).
5. **Respect lifecycle status.** Every status is searchable, including `draft`
   and `deprecated`. Say when support is only a draft, and never present a
   deprecated passage as current guidance — look for what superseded it.
6. **Say when the bundle does not answer.** No passages, or passages that do not
   support the claim, mean the knowledge is not recorded. Report that plainly,
   then answer from other evidence only if you label it as such. Do not stretch a
   near-miss into support.

## Validate

Run validation before saying a bundle conforms, and after editing one.

- Exit `0` and `PASS`: the automated gate passed. Advisory findings may remain;
  mention the relevant ones without treating them as failures.
- Exit `1` and `FAIL`: error findings exist. Report each with its `id`, path and
  message.
- Exit `2`: the bundle could not be assessed — for example an unsupported or
  missing Profile release, or a command error. Report the reason, not a verdict.

Validation is only the automated part of the Profile gate; contextual judgment
is a separate review. Route by task:

| Need | Use |
| --- | --- |
| Fix findings or write any file under the bundle | `author-knowledge-bundle` skill |
| Whole-bundle audit with a Profile Review Report | `assess-knowledge-bundle` skill |
| Seed a bundle in a repository that has none | `adopt-knowledge-bundle` skill |

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `wayfinder` not found; MCP server missing from `/mcp` | Not installed or not on the `PATH` the agent was launched with. Install the complete runtime (see the Wayfinder install guide), or set `WAYFINDER_EXECUTABLE` for the plugin. `wayfinder setup` adds the server to a project's `.mcp.json`. Restart the client after installing. |
| Wayfinder reports a newer release | `wayfinder update` upgrades the runtime and refreshes these skills. |
| Tools search the wrong bundle, or report no `knowledge/` | The MCP server serves `knowledge/` relative to where the client started. Set `WAYFINDER_KNOWLEDGE_DIR` to the bundle and restart, or use the CLI with an explicit path. |
| `Index is missing, stale or incompatible` / `Index belongs to another bundle` / `Embedding configuration changed` | Run `index` on the same bundle, then search again. |
| `Knowledge changed while indexing` / `during search` | Files changed mid-command. Let edits finish and rerun. |
| `Index is busy` | Another Wayfinder command holds this bundle. Retry after it finishes. |
| Embedding model or ObjectBox library missing or unreadable | Only part of the runtime is installed. Rerun the complete installer; copying just the executable is not enough. |
| `Wayfinder data must be outside the knowledge bundle` | `WAYFINDER_DATA_DIR` points inside the bundle. Point it elsewhere. |
