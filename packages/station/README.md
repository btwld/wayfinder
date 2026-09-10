# Station

Validate, index and search an explicit local OKF knowledge bundle:

```bash
station validate ./knowledge
station index ./knowledge
station search ./knowledge "How do I regain account access?"
```

Index and search always use local embeddings. Validation runs the existing
OKF and declared Concepta Profile checks and retains their output and exit
codes. Automated success keeps judgment rules UNASSESSED.

## Source development and packaging

From the workspace root:

```bash
dart pub get
dart run melos run objectbox:install
dart run melos run embeddings:prepare
dart run station:station validate examples/knowledge
dart run station:station index examples/knowledge
dart run station:station search examples/knowledge "How is reporting implemented?"
dart run tool/build_station.dart --offline
```

The build creates `build/station/bundle/bin/station` with native libraries and
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
| Repeat `index` | Reuse compatible vectors; encode changed/new inputs and remove deleted passages |
| `search` | Reopen the completed snapshot and encode only the query |

Titles/headings are part of document embedding inputs. Other metadata and
citation-only updates can refresh without inference. Passage shifts can change
IDs and cause additional re-encoding. An unchanged index reuses its fitted
snapshot and vectors, but still opens the model and stages a database copy.

Native first-use initialization remains variable. Reusing document vectors
does not remove model startup or the first query's inference cost. The
[initial runtime report](../../docs/knowledge_embeddings_local_search.md#model-latency-and-memory)
records the observed first-use delays and faster subsequent launches.

After editing knowledge files, run `station index` again. Search detects an
absent, stale or incompatible index and reports the indexing command; it does
not silently change retrieval methods or update document embeddings.

The validate, index and search commands accept `--output=json`. Search also accepts `--limit=1..100`
(default 5). Query text is one quoted argument. Results include original paths,
line ranges, metadata, similarity, context inclusion reasons and link notices.
All lifecycle states remain eligible and status is displayed. Ranked passages
are candidates; verify the supporting text before answering.

Validation preserves exit 0 for automated success, 1 for findings and 2 for
usage/I/O/unsupported releases. Index/search return 0 on success and 2 when they
cannot complete, including stale indexes, busy stores and missing model assets.
An empty result set is a successful search.

## MCP server

```bash
station mcp /absolute/path/to/knowledge
```

Configure a local MCP host to launch the packaged executable. For hosts using
the common `mcpServers` configuration shape:

```json
{
  "mcpServers": {
    "station": {
      "command": "/absolute/path/to/bundle/bin/station",
      "args": ["mcp", "/absolute/path/to/knowledge"]
    }
  }
}
```

The process serves one bundle over stdio; stdout is reserved for JSON-RPC.
The tools are `validate` and `index` (no arguments), and `search` with a required
`query` and optional `limit` (1–100, default 5). Their results contain the same
JSON as the commands, in one text content block. Validation also includes the
command's `exit_code`, findings and UNASSESSED judgment without treating a
completed report as a tool error.

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
server does not expose upstream OKF's concept-authoring or graph tools.

Tool argument contracts now use ACK through the adapter in
[ACK PR #140](https://github.com/conceptadev/ack/pull/140), pinned to commit
`1b54b08e522c9dee51cfa55ac69f8448bd2a3b72` with the compatible published
`ack ^1.2.0` core. The adapter applies the search default and normalizes integral
JSON numbers before the callback. It preserves the advertised nonblank query,
1–100 limit and closed-object constraints. Replace the Git dependency with a
published adapter version after that release is verified.

See [ADR-0011](../../docs/adr/0011-station-mcp.md) for the SDK release review,
protocol choices and lifecycle limits.

## Local storage

Station stores an ObjectBox database and snapshot under a hash of the canonical
absolute bundle path. Separate worktrees get separate indexes; symlink aliases
resolve to the same root. Moving a bundle requires indexing its new location.

- macOS: `~/Library/Application Support/Station/indexes/<bundle-key>/`
- Linux: `$XDG_DATA_HOME/station/indexes/<bundle-key>/`, defaulting to
  `~/.local/share/station/indexes/<bundle-key>/`
- Windows: `%LOCALAPPDATA%/Station/indexes/<bundle-key>/`

`STATION_DATA_DIR` overrides the app-data root for isolated runs. It must be
outside the knowledge bundle. The model is shared by the installation; query
vectors and history are not written to disk. These derived files include source
text and metadata and can be rebuilt from the original bundle.

An OS lock serializes same-bundle commands. Indexing stages a replacement
database and snapshot, then publishes their completed generation atomically.
Failed indexing preserves the previous generation; searches still reject it
if source files have changed. Successful indexing removes inactive generations.
Copying the database temporarily requires space for both generations.
Saved generations are decoded and validated once per operation. Indexing returns
a typed result internally while preserving the existing JSON output and saved
index format.

Source-content rechecks detect observed edits; they are not an OS filesystem
snapshot. The adapter scores eligible vectors exactly, so work increases with
corpus size. There is no background watcher or navigation-file generation.

## Verification

```bash
# From this package:
dart test
# From the workspace root, after building:
python3 tool/verify_station.py build/station/bundle --output=build/station-checks.json
python3 tool/verify_station_mcp.py build/station/bundle --output=build/station-mcp-checks.json
```

The native check copies the bundle to a temporary location and uses fresh
processes for indexing/search, vector reuse, updates/deletions, missing/corrupt
models, cross-process locking and crash-lock recovery. It checks validation
without a model and preserves the old index after an indexing failure.
The checked-in fixture is generic; it is not a conformant profile template or
independent model-quality benchmark. Native CI exercises Linux/macOS.

See [ADR-0010](../../docs/adr/0010-station-cli.md) for the application decision
and [the retrieval evidence](../../docs/knowledge_embeddings.md) for model and
ranking limitations. Existing `okfp` installations continue to work.
