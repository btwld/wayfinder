---
name: use-wayfinder
description: Search, index, validate, and project the relationship graph of a project's OKF knowledge bundle with Wayfinder, through its MCP tools or the wayfinder CLI. Use whenever a question may be answered by the project's recorded knowledge — decisions, requirements, conventions, ownership, rationale, prior analysis — before answering from memory or grepping; whenever a bundle changed and search must see it; before claiming a bundle passes validation; and when you need the ordinary OKF concept graph.
---

# Using Wayfinder

Wayfinder is a local tool for an Open Knowledge Format (OKF) knowledge bundle,
usually `knowledge/` in the project root. It does four things: **validate** the
bundle against OKF and its selected Bitwild or legacy Concepta Profile release, **index** it into
saved local embeddings, **search** that index for cited passages, and **graph**
the ordinary OKF relationship graph. Nothing is sent off the machine, and
indexing writes only derived data outside the bundle. Graph is a live
projection, not a source of truth; Mermaid and DOT are text for an external
preview.

Its value is grounding: an answer built from cited passages of the project's own
recorded decisions beats one built from general knowledge or a keyword grep that
misses paraphrases. So when a question touches what the project decided, requires,
owns, or learned, search first and answer from what you find.

## Session startup and index refresh

`wayfinder setup --session-hooks` prompts Claude, Codex, and Gemini to load this
skill at session start. Grok reads the same pointer from `AGENTS.md`; its
SessionStart hook ignores stdout. Follow the related skills below only when the
task calls for them. Startup supplies instructions and performs no indexing.

`wayfinder setup --hooks` installs bundle-aware Git hooks for pulls, checkouts,
and rebases. When search reports a stale index, run the MCP `index` tool or
`wayfinder index <bundle>` and search again.

## Choose an interface

Prefer the **Wayfinder MCP tools** when they are available (the `wayfinder`
plugin registers them as `validate`, `index`, `search` and `graph`). They are bound to one
bundle — `knowledge/` by default, or `WAYFINDER_KNOWLEDGE_DIR` — so they take no
path. `search` takes `query` and an optional `limit` (1–100, default 5).
`graph` takes optional `types`, `path_prefixes` and `resolutions` and returns
the versioned OKF graph JSON, plus a `field_edges` array holding each concept's
typed `relationships` entries.

Otherwise use the **CLI**. Search/index default to all project bundles listed by
the nearest `wayfinder.json`, or conventional `knowledge/` without configuration.
Use `--bundle <folder-name>` to filter; explicit paths still select one bundle:

```sh
wayfinder validate <bundle> [--config=wayfinder.json] [--fix] [--output=json|sarif]
wayfinder graph <bundle> [--output=json|mermaid|dot] [--type TYPE] [--path-prefix PREFIX] [--resolution STATE]
wayfinder index [<bundle>] [--bundle NAME] [--output=json]
wayfinder search [<bundle>] "<one quoted query>" [--bundle NAME] [--limit N] [--output=json]
```

Project search ranks across selected bundles with a global limit. Its JSON adds
`bundles` and annotates each match/context hit with `bundle` and `bundlePath`;
combine that path with `chunk.sourcePath` for project-relative citations. A stale
selected index fails the whole search: run `wayfinder index` and retry. Explicit
paths preserve the single-bundle JSON shape. Do not combine a path and `--bundle`.

`--type`, `--path-prefix` and `--resolution` are repeatable and match the MCP
`types`, `path_prefixes` and `resolutions` filters.

Use `--output=json` when you will parse results; explicit-path output has the
same shape the MCP tools return. If neither the tools nor the `wayfinder` command exist, say so and
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
     link from a match — `viaPath` names that match, and `relationship` names
     the typed relationship when one was followed), or `governing` (a governing
     source pulled in ahead of the passage it governs).
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
7. **Know what search does not see.** `index.md` and `log.md` are navigation and
   history, not indexed passages: open them directly for "where do I start" or
   "what changed" questions. Facts that live only inside fenced code blocks (a
   version declaration, a naming pattern) rank low for natural-language queries;
   when the first query returns the prose around such a block, retry with the
   literal keywords. Raw material kept outside the bundle (for example a
   `captures/` evidence layer) is never indexed; cite it through the concept
   that names it in `sources`.

## Validate

Run validation before saying a bundle conforms, and after editing one.
For a configured 2026.3 bundle, `validate` reads only a current lock/cache:
it never fetches or writes. `--fix` is the one exception to read-only
validation: for a 2026.3 bundle it first writes okf's generated indexes, then
validates; it never writes a 2026.2 bundle or one OKF rejects. A missing or
stale lock still leaves an independent
OKF result; run `wayfinder get` to resolve the declared source, or
`wayfinder upgrade` only when intentionally advancing a mutable ref.
`graph`, `index`, and `search` do not need Profile-source resolution.

- Exit `0` and `PASS`: the automated gate passed. Advisory findings may remain;
  mention the relevant ones without treating them as failures. Summary entries
  (`profile.summary`, or the text `Summary:` block) report what the Profile
  permits, such as a project type in use or a planned link; they are never
  findings.
- Exit `1` and `FAIL`: error findings exist. Report each with its `id`, path and
  message.
- Exit `2`: the bundle could not be assessed — for example an unsupported or
  missing Profile release, or a command error. Report the reason, not a verdict.

Validation is only the automated part of the Profile gate; contextual judgment
is a separate review. Route by task:

| Need | Use |
| --- | --- |
| Fix findings or write any file under the bundle | [author-knowledge-bundle](../author-knowledge-bundle/SKILL.md) |
| Whole-bundle audit with a Profile Review Report | [assess-knowledge-bundle](../assess-knowledge-bundle/SKILL.md) |
| Seed a bundle in a repository that has none | [adopt-knowledge-bundle](../adopt-knowledge-bundle/SKILL.md) |

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
