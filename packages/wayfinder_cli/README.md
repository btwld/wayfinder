# Wayfinder

Validate, index, search and project an explicit local OKF knowledge bundle:

```bash
wayfinder validate ./knowledge
wayfinder graph ./knowledge --output mermaid
wayfinder index ./knowledge
wayfinder search ./knowledge "How do I regain account access?"
```

Index and search always use local embeddings. Validation runs the existing
OKF and declared Concepta Profile checks and retains their output and exit
codes. Automated success keeps judgment rules UNASSESSED.

## Native installation

For indexing and search without a Dart SDK, install the complete runtime from
[the installation guide](https://github.com/btwld/wayfinder/blob/main/docs/install.md).
It includes Wayfinder with built-in Profile validation, the embedding model and required native libraries.
The GitHub repository hosts the source, plugin and native release archives.

## Dart installation

Requires Dart 3.11.0 or later. Install the development release:

```bash
dart pub global activate wayfinder_cli
wayfinder validate ./knowledge
```

Add the Dart pub cache's `bin` directory to your `PATH` if `wayfinder` is not found.
Validation and MCP discovery work without model weights. Indexing and search
also require the verified embedding model and native libraries; pub.dev does
not distribute these assets with this package. Use the native installer above, or the source preparation and bundle build
below, for the complete retrieval installation.

## Source development and packaging

From the workspace root:

```bash
dart pub get
dart run melos run objectbox:install
dart run melos run wayfinder_embeddings:prepare
dart run wayfinder:wayfinder validate examples/knowledge
dart run wayfinder:wayfinder index examples/knowledge
dart run wayfinder:wayfinder search examples/knowledge "How is reporting implemented?"
dart run tool/build_wayfinder.dart --offline
```

The build creates `build/wayfinder/bundle/bin/wayfinder` with native libraries and
the pinned 25.28 MB Arctic XS model. Distribute the whole `bundle/` directory.
Model size is only part of the installation size. `--offline` requires staged
or cached model weights; native build hooks have their own cache.

Preparation downloads and verifies model weights. It generates no document
embeddings. Runtime inference loads verified local weights through llamadart;
there is no model download command or external embedding service.
Source runs resolve the prepared embedding package's model/library. Packaged
runs resolve their own assets independently of the current working directory.

## Embedding lifecycle

| Action | Embedding work |
| --- | --- |
| `validate` | None |
| First `index` | Fit passages to the tokenizer, embed them and persist a completed snapshot |
| Repeat `index`, nothing changed | None; returns without loading the model |
| Repeat `index` after edits | Reuse compatible vectors; encode changed/new inputs and remove deleted passages |
| `index --force` | Discard the saved index and re-embed every passage |
| `search` | Reopen the completed snapshot and encode only the query |

Titles/headings are part of document embedding inputs. Other metadata and
citation-only updates can refresh without inference. Passage shifts can change
IDs and cause additional re-encoding. An unchanged index returns without
opening the model or staging a database copy. `--force` rebuilds from scratch
into a new generation, which replaces the old one only when it completes.
`--detach` returns at once and indexes in a background process only when the
bundle changed; the refresh hooks use it.

### Oversized-input recovery and warnings

Indexing losslessly subdivides oversized passages, including long separators and
identifiers, using the actual tokenizer. If a derived title/heading prefix
prevents fitting, indexing retries that original chunk without the prefix.
Source files are never edited; fitted fragments reconstruct each pre-fit passage,
not the entire document. Metadata and source citations remain available. An
irreducible body-only input or a tokenizer/inference error still fails indexing.

Completed and current foreground index results include `warnings` (an empty
array when none). Each warning has `code`, `sourcePath`, `lineStart`, `lineEnd`,
and `affectedChunks`, counting original chunks once per code and enclosing their
line ranges. Codes are `oversized_segment_split` and
`embedding_context_omitted`; ordinary whitespace splitting is silent. Warnings
are sorted by source path, then code.

Human-readable indexing prints warnings to stderr with single-line escaped paths.
CLI JSON and MCP return the same structured warnings in their existing payload;
MCP still uses one JSON text block. Successful recovery keeps exit status 0.
Saved warnings replay on current-index calls without loading the model. Detached
launch/current/running acknowledgements keep their status-only shape; once a
background index completes, the next foreground call reports its saved warnings.
Consumers enforcing a closed JSON response shape must allow the new `warnings`
field.

This changes application index configuration from version 2 to 3. Run
`wayfinder index <bundle>` once to rebuild even if source bytes are unchanged;
subsequent unchanged calls reuse the index. Snapshot version 1 remains readable
with additive recovery fields. No bundle migration, Profile release, model change,
or ObjectBox schema change is required. New fragment boundaries or omitted context
can change retrieval results. Failed rebuilds preserve the previous generation,
but search still rejects stale or configuration-incompatible indexes; there is
no automatic fallback to old vectors.

Native first-use initialization remains variable. Reusing document vectors
does not remove model startup or the first query's inference cost. The
[initial runtime report](../../docs/wayfinder_embeddings_local_search.md#model-latency-and-memory)
records the observed first-use delays and faster subsequent launches.

After editing knowledge files, run `wayfinder index` again. Search detects an
absent, stale or incompatible index and reports the indexing command; it does
not silently change retrieval methods or update document embeddings.

`graph` reads the live bundle and projects the ordinary OKF relationship
graph. It does not open the search index or model. `--output` is
`json` (default), `mermaid`, or `dot`. Mermaid and DOT are text for an
external preview such as mermaid.live; they are not a rendered picture.
Repeatable `--type`, `--path-prefix` and `--resolution` select an induced
subgraph, matching `okf graph`. Load findings print the OKF report and
refuse a graph.

The validate, index and search commands accept `--output=json`. Search also accepts `--limit=1..100`
(default 5). Query text is one quoted argument. Results include original paths,
line ranges, metadata, similarity, context inclusion reasons and link notices.
All lifecycle states remain eligible and status is displayed. Ranked passages
are candidates; verify the supporting text before answering.

Validation preserves exit 0 for automated success, 1 for findings and 2 for
usage/I/O/unsupported releases. Index/search return 0 on success and 2 when they
cannot complete, including stale indexes, busy stores and missing model assets.
An empty result set is a successful search. Graph returns 0 on success, 1 when
load findings refuse a graph, and 2 for usage or I/O failure.

## MCP server

```bash
wayfinder mcp /absolute/path/to/knowledge
```

Configure a local MCP host to launch the packaged executable. For hosts using
the common `mcpServers` configuration shape:

```json
{
  "mcpServers": {
    "wayfinder": {
      "command": "/absolute/path/to/bundle/bin/wayfinder",
      "args": ["mcp", "/absolute/path/to/knowledge"]
    }
  }
}
```

The process serves one bundle over stdio; stdout is reserved for JSON-RPC.
The tools are `validate` and `index` (no arguments), `search` with a required
`query` and optional `limit` (1–100, default 5), and `graph` with optional
`types`, `path_prefixes` and `resolutions`. Their results contain the same
JSON as the commands, in one text content block. Validation also includes the
command's `exit_code`, findings and UNASSESSED judgment without treating a
completed report as a tool error. `graph` returns the versioned OKF graph JSON
(`schema_version: "1"`). Mermaid and DOT remain CLI text for an external
preview.

Use `index` explicitly before the first search and after source edits. It saves
document embeddings in the same local app-data directory used by the CLI.
Discovery and validation work without a model. Search reports missing/stale
indexes and never indexes implicitly. The host can require approval for index's
local writes. There is no per-call bundle override or retrieval-mode option.

The server currently opens and closes the encoder for each index/search call;
a long-lived connection does not yet keep the model warm. Configure the host's
tool timeout for first-use startup and the size of the corpus. Overlapping
retrieval calls can return a busy error. On disconnect, active operations finish
and release their resources; cancellation does not roll back indexing. The
server projects the ordinary OKF graph and does not expose upstream OKF's
concept-authoring write tools. See [ADR-0012](../../docs/adr/0012-wayfinder-graph-projection.md).

Tool argument contracts use ACK through the published `ack_mcp_dart ^1.3.0`
adapter and the compatible `ack ^1.2.0` core. The adapter applies the search
default and normalizes integral JSON numbers before the callback. It preserves
the advertised nonblank query, 1–100 limit and closed-object constraints.

See [ADR-0011](../../docs/adr/0011-station-mcp.md) for the SDK release review,
protocol choices and lifecycle limits.

## Agent skills, project setup and updates

```bash
wayfinder skills install [--agent=all|claude|agents]
wayfinder skills status
wayfinder setup [<project>] [--bundle=knowledge] [--hooks]
wayfinder update [--check] [--version=<version>]
```

Native bundles include the skill family. `skills install` uses the `wayfinder`
Claude Code plugin when the `claude` CLI is available, otherwise copies the
skills to `~/.claude/skills`. It also copies them to `~/.agents/skills` for Codex
and other Agent Skills clients. It marks its copies and never replaces or
removes a skill it did not install. `setup` adds `wayfinder mcp <bundle>` to a
project's `.mcp.json` and preserves other servers. `setup --hooks` also runs
`wayfinder index <bundle> --detach` after Claude Code and Codex turns (Stop hooks
in `.claude/settings.json` and `.codex/hooks.json`) and after git pulls,
checkouts and rebases (`.githooks/`, enabled with `core.hooksPath`). Existing
hooks are kept, and rerunning replaces only Wayfinder's own entries.

`update` reruns the release's verified installer for installer-managed
runtimes, then refreshes the skills and plugin. A Dart installation prints its
upgrade command instead; the Homebrew formula is no longer updated, so a
Homebrew installation is told to reinstall with the install script. Interactive commands also print a one-line
stderr notice when a newer stable release exists. That check is the only
network request Wayfinder makes on its own: at most once a day it reads the
GitHub Releases API and sends no bundle content. It never runs for `mcp`, when
stderr is not a terminal, or when `CI` or `WAYFINDER_NO_UPDATE_CHECK` is set.

## Local storage

Wayfinder stores an ObjectBox database and snapshot under a hash of the canonical
absolute bundle path. Separate worktrees get separate indexes; symlink aliases
resolve to the same root. Moving a bundle requires indexing its new location.

- macOS: `~/Library/Application Support/Wayfinder/indexes/<bundle-key>/`
- Linux: `$XDG_DATA_HOME/wayfinder/indexes/<bundle-key>/`, defaulting to
  `~/.local/share/wayfinder/indexes/<bundle-key>/`
- Windows: `%LOCALAPPDATA%/Wayfinder/indexes/<bundle-key>/`

`WAYFINDER_DATA_DIR` overrides the app-data root for isolated runs. It must be
outside the knowledge bundle. The model is shared by the installation; query
vectors and history are not written to disk. The saved snapshot holds a complete
copy of the indexed bundle text with its metadata, so `wayfinder index` places that
knowledge in per-user application data on every machine that runs it. Nothing
leaves the machine; deleting the index directory removes the copy, and indexing
rebuilds it from the original bundle.

An OS lock serializes same-bundle commands. Indexing stages a replacement
database and snapshot, then publishes their completed generation atomically.
Failed indexing preserves the previous generation; searches still reject it
if source files have changed. Successful indexing removes inactive generations.
Copying the database temporarily requires space for both generations.
Saved generations are decoded and validated once per operation. Indexing returns
a typed result internally, with additive JSON warnings and backward-readable
snapshot recovery data.

Source-content rechecks detect observed edits; they are not an OS filesystem
snapshot. The adapter scores eligible vectors exactly, so work increases with
corpus size. There is no background watcher or navigation-file generation.

## Verification

```bash
# From this package:
dart test
# From the workspace root, after building:
python3 tool/verify_wayfinder.py build/wayfinder/bundle --output=build/wayfinder-checks.json
python3 tool/verify_wayfinder_mcp.py build/wayfinder/bundle --output=build/wayfinder-mcp-checks.json
```

The native check copies the bundle to a temporary location and uses fresh
processes for indexing/search, vector reuse, updates/deletions, missing/corrupt
models, cross-process locking and crash-lock recovery. It checks validation
without a model and preserves the old index after an indexing failure.
The checked-in fixture is generic; it is not a conformant profile template or
independent model-quality benchmark. Native CI exercises Linux/macOS.

See [ADR-0010](../../docs/adr/0010-station-cli.md) for the application decision
and [the retrieval evidence](../../docs/wayfinder_embeddings.md) for model and
ranking limitations. Existing `okfp` installations continue to work.

CLI and MCP search share the ACK query, limit, and default contract. The CLI
converts integer argument text before validation; MCP accepts JSON integers,
including integral JSON numbers such as `2.0`. Invalid arguments fail before
opening retrieval resources. Whitespace-only queries include Unicode NEXT LINE
(`U+0085`), preserving the CLI rule in MCP as well.

## License

Wayfinder is distributed under the BSD 3-Clause license in [LICENSE](LICENSE).
Dependencies and separately downloaded models/native libraries retain their
own licenses. The repository's OKF Profile materials retain their existing
license.

## Moving from the Station prototype

Use `wayfinder` in place of `station` and `WAYFINDER_DATA_DIR` in place of
`STATION_DATA_DIR`. Default app-data directories now use `Wayfinder` on
macOS/Windows and `wayfinder` on Linux. Run `wayfinder index <bundle>` to build
the index at its new location. Existing Station data is left intact.

To deliberately reuse the previous location, point `WAYFINDER_DATA_DIR` at it;
normal index compatibility checks still apply. Update MCP executable paths.
The `okfp` command and knowledge bundle format are unchanged.

## Upgrading the retrieval package

Wayfinder 0.0.1-dev.1 uses `wayfinder_embeddings`. Existing Wayfinder indexes
remain compatible; no model, schema UID or vector-identity change is introduced
by the package rename. Keep the complete native bundle together when upgrading.

Set `WAYFINDER_EMBEDDING_MODEL` to select a verified local model file. The old
`KNOWLEDGE_EMBEDDING_MODEL` remains a fallback when the new variable is absent.
An invalid explicit setting fails instead of selecting another model.

Native builds check the installed and packaged ObjectBox bytes against pinned
platform hashes and include its license and attribution. See the
[ObjectBox build review](../../docs/objectbox-build-review.md).
