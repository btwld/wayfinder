# ADR-0018: Embeddable project and retrieval libraries

- Status: accepted
- Date: 2026-10-22
- Scope: the public Dart entries, what a host injects, Wayfinder's lock files, and the CLI's role; no Profile rule and no change to results
- Builds on [ADR-0010](0010-wayfinder-cli.md), [ADR-0011](0011-wayfinder-mcp.md) and [ADR-0012](0012-wayfinder-graph-projection.md)

## Context

A host such as an IDE or an agent runtime needs what the `wayfinder` command
does, in process: find a project's bundles, resolve and select its Profiles,
validate, project the graph, and later index and search. In 0.2 that code
lived in `wayfinder_cli/lib/src`, which no dependent may import, and it
assumed one short-lived CLI process. It inherited the caller's Git
environment, reached a fixed data directory, and could not be cancelled.

Dart's `RandomAccessFile.lock` is a `fcntl` record lock on POSIX. It belongs
to the process, so two isolates of one process do not exclude each other, and
closing any descriptor of the file, even one opened only to read it, releases
the lock. okf's bundle lock (`.okf.lock`) is built on it, and okf documents
that a multi-isolate application must serialize its own bundle access.

## Decision

**Public entries.** `package:wayfinder/wayfinder.dart` keeps validation and
adds `ProfileValidator.validateLoaded`, which validates a bundle okf already
loaded and reads no bundle file (only `path-targets-exist` still checks, on
disk relative to the bundle root, a link target okf's graph cannot resolve
inside the bundle), and `ProfileProjection.generatedFiles`, the files `--fix`
would write.
`package:wayfinder/project.dart` holds project discovery, the data directory,
Profile resolution and selection, validation from that selection, the graph
projection with its Ack input, cancellation, the Git runner and the file lock.
The index lifecycle follows the same pattern as a `wayfinder_embeddings`
entry. The core depends on none of `wayfinder_embeddings`, ObjectBox,
llamadart or analyzer.

**The host owns its resources.** The project library never downloads,
prompts, loads a native library from disk or resolves files next to the
executable; the retrieval library takes the same rule when its index
lifecycle leaves the CLI. Its one download is the embedding model, made only
when a host calls `EmbeddingModelCache.provision`
([ADR-0010](0010-wayfinder-cli.md)). A host injects the
data directory (`WayfinderDataDirectory.resolve()` by default), a `GitRunner`
(`runGit` by default), a `WayfinderCancellation`, and the validator's okf
loader and graph builder. Failures are `WayfinderException`s with a stable
`code` beside the message the CLI prints.

**Git runs hardened and bounded.** `runGit` drops the `GIT_*` variables a
hook or linked worktree exports, such as `GIT_DIR`. It keeps only those that
choose Git's configuration files (`GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`,
`GIT_CONFIG_NOSYSTEM`) or its SSH command (`GIT_SSH_COMMAND`, `GIT_SSH`,
`GIT_SSH_VARIANT`). It never prompts: it tells Git and a credential manager
not to (`GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`), and runs SSH in
batch mode. SSH is the command Git would choose
(`GIT_SSH_COMMAND`, then `core.sshCommand`, then `GIT_SSH`, then `ssh`), with
`-o BatchMode=yes` added when it is OpenSSH; another client, such as `plink`,
runs unchanged. Before a command that may reach a remote, one more hardened
`git config` call reads `core.sshCommand` as that command sees it. `runGit`
also skips Git LFS downloads, disables hooks, the filesystem monitor and the
`ext::` transport, and closes stdin. It kills a command with its children on
cancellation, or once the command writes nothing for its timeout; a clone
reports progress, so a long clone keeps running. Git output is bytes
(`GitResult`), because skill files are blobs. A host's own runner applies the
same options and environment.

**Resolution is plan, then apply.** `plan` resolves and composes every chain
and may clone or refresh a source in the cache, but writes nothing in the
project. `apply` writes the lock and skills and refuses a plan whose
configuration, lock or cached package files changed since (`resolution-stale`).
`resolve` is both under one hold of the project's lock. A plan keeps the
package file of each package it reads, so `select`, the selection validation
uses, reads files only and never runs Git. A cache Wayfinder 0.2 wrote has the
mirrors but no package files: when `select` finds no Profile,
`validateWithProfileSources` copies the missing files out of the existing
mirrors with `git show` (`restoreCachedPackages`), never fetching, and
selects again.

**Wayfinder's lock files use `WayfinderFileLock`.** It is `flock(2)` on a
descriptor of its own through `dart:ffi` on POSIX, and `RandomAccessFile.lock`
on Windows, whose `LockFileEx` lock belongs to its handle. Both hold across
processes and across the isolates of one process, and closing another
descriptor never releases them. A lock file stays in place on release.

| Resource | Lock file under the data directory | Mode | On contention |
| --- | --- | --- | --- |
| A Profile source's mirror, while a plan clones, refreshes or reads it | `profiles/<sha256(location)>.lock` | exclusive, waits up to 120 s; restoring package files never waits | waits, then `resolution-busy`; restoring skips the mirror |
| A project's `get` | `projects/<sha256(root)>.get.lock` | exclusive, never waits | `resolution-busy` |

A plan holds one mirror's lock at a time, so two plans never deadlock. The
project lock records the project root it protects, so a later cleanup can
tell which lock belongs to a root that no longer exists. Read that note only
while the lock is free (`isHeld` is false): on Windows the lock is a mandatory
byte-range lock, so no other handle reads a held lock file. No lock file is
kept for compatibility with an earlier release: `flock` and `fcntl` locks do
not exclude each other. The index lifecycle keeps its own lock until its storage
changes ([ADR-0010](0010-wayfinder-cli.md)).

**One isolate per process does okf bundle I/O.** okf's bundle lock does not
exclude isolates, so a process runs all okf bundle I/O on one isolate:
validate, graph, read, write, adoption, `--fix`, index and search. Wayfinder's
own locks need no such rule; a host may resolve Profiles on any isolate.

**The CLI is a shell.** `wayfinder_cli` parses arguments, chooses output
formats and exit codes, serves MCP, and owns what only an installed command
needs: `--detach`, the update check, `setup`, `skills` and `session-context`.
It holds no logic a host would have to copy.

## Consequences

Hosts embed discovery, resolution, selection, validation and the graph
without the CLI. With a complete cache, validation spawns no process; it runs
`git show` only to restore a package file a 0.2 cache lacks. The CLI's output
and exit codes are unchanged, including on a 0.2 cache. A host that calls
`select` itself sees such a cache as `wayfinder/profile-unresolved` until it
calls `restoreCachedPackages` or `resolve`.

Git settings made through other `GIT_*` variables, such as `GIT_SSL_CAINFO`
or `GIT_ASKPASS`, no longer reach resolution; put them in Git's configuration
(`http.sslCAInfo`, a credential helper). A user's own SSH command still runs.

Lock files and package files accumulate in the data directory, which stays
derived and removable. `flock` is only as strong as the filesystem: keep the
data directory on a local disk.

## Reconsider when

okf's bundle lock excludes isolates, Dart gains a per-descriptor file lock, or
a host needs okf bundle I/O on several isolates of one process.
