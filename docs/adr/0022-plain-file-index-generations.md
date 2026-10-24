# ADR-0022: Keep indexes as plain-file generations

- Status: accepted
- Date: 2026-10-24
- Scope: the index lifecycle, what search reads during a refresh, and the public knowledge store; no Profile rule
- Amends: [ADR-0010](0010-wayfinder-cli.md), [ADR-0011](0011-wayfinder-mcp.md) and [ADR-0018](0018-embeddable-libraries.md)

## Context

ADR-0010 stored one ObjectBox index per bundle and had search refuse a stale
index. ADR-0011 failed a search that overlapped another retrieval call. The
index lifecycle then moved into a library a host can embed, and the storage
became plain files so a search can read the last published index while a
refresh runs. Those three records stay as they were accepted; this record
carries the change.

## Decision

- One index per canonical bundle path and configuration, under
  `indexes/bundles/<bundle key>/<configuration key>/`. The configuration key
  includes chunking, storage and the encoder identity, plus the reviewed
  llama.cpp release (`wayfinderLlamaCppRuntime`). Chunk ids hash the
  bundle-relative path, so two worktrees of one bundle rank alike. Indexes
  from 0.2, and from an ObjectBox-backed 0.3 build, are left in place and
  not read.
- A generation is `snapshot.json` plus `vectors.f32` (a header and one
  little-endian float32 row per passage). Publishing replaces a `current`
  pointer. Search loads that generation and scores every eligible vector.
  Rankings are the ObjectBox rankings: the stored values are the same, and
  the HNSW index was never used.
- Only writers take `writer.lock`. A second writer gets `index-busy` and
  does not wait. `status` and search take no lock. They read the published
  generation, which nothing mutates, so a search during a refresh keeps
  working. The application then adds a `refresh-in-progress` notice, and
  `source-changed` where files moved, with `sourceChanged` on those
  citations. Each notice has a stable code, its sentence and the paths it
  concerns. With no refresh running, a stale index is still refused. The
  library refuses by default.
- `forget` and `forgetProjectRoot` delete the indexes they name, their lock
  files and the directories that leaves empty. They take every writer lock
  first. If a `current` pointer cannot be removed, they put back any pointer
  already removed and delete nothing (`index-busy`). A generation a reader
  on Windows still has open stays, with its lock file, for a later `prune`.
- `package:wayfinder_embeddings/knowledge_store.dart` is that lifecycle.
  The host injects the data directory and a `WayfinderEncoderProvider`.
  The model is downloaded only by `EmbeddingModelCache.provision` and
  deleted only by `EmbeddingModelCache.remove`. The store needs no database
  library. MCP shares one encoder, one model call at a time, so a search
  runs between an index's batches. A search the client cancels, or one still
  running at disconnect, stops. An index runs to its end.
- `WayfinderFileLock.tryExclusive` retries a refused lock for up to 100 ms,
  so an `isHeld` probe is not a holder. After it locks, it checks that the
  path still names that file and opens the path again when it does not.

## Consequences

A search during a refresh can cite the previous generation. Its notices say
so. Upgrading builds each index once. `flock` is only as strong as the
filesystem: keep the data directory on a local disk.
