# ADR-0018: Embeddable project and retrieval libraries

- Status: accepted
- Date: 2026-10-22
- Updated: 2026-10-22 (the knowledge store entry and its index lock; a host's fetch policy, and adoption holding the project's `get` lock, with [ADR-0020](0020-programmatic-adoption.md)); 2026-10-22 (a host's root bounds discovery and binding; required concept fields and installed skill text are public)
- Scope: the public Dart entries, what a host injects, Wayfinder's lock files, and the CLI's role; no Profile rule, and no change to the command's results
- Builds on [ADR-0010](0010-wayfinder-cli.md), [ADR-0011](0011-wayfinder-mcp.md) and [ADR-0012](0012-wayfinder-graph-projection.md)

## Context

A host such as an IDE or an agent runtime needs what the `wayfinder` command
does, in process: find a project's bundles, resolve and select its Profiles,
validate, project the graph, index and search. In 0.2 that code lived in
`wayfinder_cli/lib/src`, which no dependent may import, and it assumed one
short-lived CLI process. It inherited the caller's Git environment, reached
a fixed data directory, found the model and ObjectBox's native library next
to its own executable, and could not be cancelled.

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
would write. `EffectiveProfile.requiredConceptFields` lists the frontmatter
keys every concept must carry: those an error rule's `frontmatter` schema
check names in a `required` it applies unconditionally. A host can then say
what a concept needs without evaluating rules.
`package:wayfinder/project.dart` holds project discovery, the data directory,
Profile resolution and selection, validation from that selection, the graph
projection with its Ack input, cancellation, the Git runner and the file lock.
`ProfileSkills.read` returns a Profile skill's installed `SKILL.md` only when
its marker holds the locked revision, the check behind
`profile-skill-stale`. It takes no lock: it reads the marker again after the
text, so a concurrent `get` never makes it return another revision's text.
`package:wayfinder_embeddings/knowledge_store.dart` holds the index
lifecycle: `WayfinderKnowledgeStore` reports a bundle's index `status`,
indexes it with progress events and cancellation, searches one bundle or a
project's bundles ranked together, and `forget`s and `prune`s indexes. Its
results are typed citations with the CLI's JSON and Markdown renderings, and
it exports the Ack inputs of host search tools, `wayfinderSearchInput` and
`knowledgeMetadataFilterInput`. `package:wayfinder_embeddings/testing.dart`
has `DeterministicTestEmbedder`, whose word-hash vectors test mechanisms
without a model, as [ADR-0017](0017-dense-only-retrieval.md) allows. The
core depends on none of `wayfinder_embeddings`, ObjectBox, llamadart or
analyzer.

**The host owns its resources.** Neither library downloads, prompts, loads
a native library from disk or resolves files next to the executable. A host
injects the data directory (`WayfinderDataDirectory.resolve()` by default),
a `GitRunner` (`runGit` by default), a `WayfinderCancellation`, and the
validator's okf loader and graph builder. The knowledge store also takes a
`WayfinderEncoderProvider`, whose identity names the index without opening a
model, such as `LocalModelEncoderProvider` over a model file the host
located and the store verifies before loading, and optionally a loader that
makes ObjectBox's library available before the first database opens. The
CLI's `native_runtime.dart` is that host: it finds the model and ObjectBox
in its bundle or in the package during development, and skips loading when
the process already provides ObjectBox's symbols. Failures are
`WayfinderException`s with a stable `code` and a sentence that names no
command; the CLI adds what to run, such as `Run wayfinder index <bundle>.`

**A host's root bounds the project.** A host knows the workspace or
worktree it opens, and a `wayfinder.json` or Git boundary above it, such as
one in a home directory, is not that project's. `WayfinderProject.discover`
therefore reads nothing above the root it is given: the bundles are those
the root's own `wayfinder.json` applies to, or its `knowledge/` directory.
Binding takes the same bound: with `projectRoot`, the search for a bundle's
`wayfinder.json` climbs the same directories as without it but reads only
those whose real path is that root or inside it, and stops there, so a
bundle with none there reports `config-missing`. Adoption's closing
validation binds within the root it adopted. The command still finds the
project from any directory inside it by asking for its search of ancestors
(`searchAncestors: true`) and binding without a bound, so its results and
exit codes are unchanged. `projectRoot` is a host input like `configPath`:
it narrows where a library caller's search looks, as `--config` names the
file outright, while the command's search, the diagnostic and how a package
reads stay as the guide states them. It therefore needs no guide §9 entry
and no format bump.

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
project. A host's `ProfileFetchPolicy` decides each clone or refresh just
before it runs, including one of a chain parent's source that the
configuration never names; a refused fetch throws
`ProfileFetchRequiredException` (`fetch-required`), which names it, so the
host can ask the person and plan again. `apply` writes the lock and skills
and refuses a plan whose configuration, lock or cached package files changed
since (`resolution-stale`). `resolve` is both under one hold of the project's
lock. A plan keeps the package file of each package it reads, so `select`, the
selection validation uses, reads files only and never runs Git. A cache
Wayfinder 0.2 wrote has the mirrors but no package files: when `select` finds
no Profile, `validateWithProfileSources` copies the missing files out of the
existing mirrors with `git show` (`restoreCachedPackages`), never fetching,
and selects again.

**Wayfinder's lock files use `WayfinderFileLock`.** It is `flock(2)` on a
descriptor of its own through `dart:ffi` on POSIX, and `RandomAccessFile.lock`
on Windows, whose `LockFileEx` lock belongs to its handle. Both hold across
processes and across the isolates of one process, and closing another
descriptor never releases them. A lock file stays in place on release.

| Resource | Lock file under the data directory | Mode | On contention |
| --- | --- | --- | --- |
| A Profile source's mirror, while a plan clones, refreshes or reads it | `profiles/<sha256(location)>.lock` | exclusive, waits up to 120 s; restoring package files never waits | waits, then `resolution-busy`; restoring skips the mirror |
| A project's `get`, or its adoption ([ADR-0020](0020-programmatic-adoption.md)) from the check step until every step has finished or been undone | `projects/<sha256(root)>.get.lock` | exclusive, never waits | `resolution-busy` |
| A bundle's index for one configuration, during any store operation | `indexes/<bundle key>/<configuration key>.lock` | exclusive, never waits | `index-busy` |

A plan holds one mirror's lock at a time, so two plans never deadlock. The
project lock records the project root it protects, so a later cleanup can
tell which lock belongs to a root that no longer exists. Read that note only
while the lock is free (`isHeld` is false): on Windows the lock is a mandatory
byte-range lock, so no other handle reads a held lock file. No lock file is
kept for compatibility with an earlier release: `flock` and `fcntl` locks do
not exclude each other. Every store operation holds its index's lock, reads
included, so a search during an index is still refused until reads stop
needing it ([ADR-0010](0010-wayfinder-cli.md)). The index lock records the
bundle root, and its modification time is the index's last use; it sits
beside the index directory, so `forget` and `prune` delete that directory
while holding it and keep the lock file. Only `prune` deletes a lock file,
and only once it has gone unused for the prune's period: deleting one that
another operation has just opened would let that operation and the next hold
different files.

**One isolate per process does okf bundle I/O.** okf's bundle lock does not
exclude isolates, so a process runs all okf bundle I/O on one isolate:
validate, graph, read, write, adoption, `--fix`, index and search. Wayfinder's
own locks need no such rule; a host may resolve Profiles on any isolate.

**The CLI is a shell.** `wayfinder_cli` parses arguments, chooses output
formats and exit codes, serves MCP, and owns what only an installed command
needs: `--detach`, the update check, `setup`, `skills` and `session-context`.
It holds no logic a host would have to copy.

## Consequences

Hosts embed discovery, resolution, selection, validation, the graph,
indexing and search without the CLI, and test against the store with the
deterministic encoder. With a complete cache, validation spawns no process; it runs
`git show` only to restore a package file a 0.2 cache lacks. The CLI's output
and exit codes are unchanged, including on a 0.2 cache. A host that calls
`select` itself sees such a cache as `wayfinder/profile-unresolved` until it
calls `restoreCachedPackages` or `resolve`.

Git settings made through other `GIT_*` variables, such as `GIT_SSL_CAINFO`
or `GIT_ASKPASS`, no longer reach resolution; put them in Git's configuration
(`http.sslCAInfo`, a credential helper). A user's own SSH command still runs.

Lock files and package files accumulate in the data directory, which stays
derived and removable; `prune` removes the indexes of bundles that no longer
exist at once, and their lock files once those go unused for its period, by
default 30 days. A holder also checks that its lock file still exists, so
the only remaining race needs an operation to open a lock file unused for
that long in the moment `prune` deletes it, and another to start on that
index meanwhile; it costs at worst a rebuild, and the publishing operation
that loses reports `index-busy`. A `prune` with a short period widens that
window. `flock` is only as strong as the filesystem: keep the data directory
on a local disk.

## Reconsider when

okf's bundle lock excludes isolates, Dart gains a per-descriptor file lock, or
a host needs okf bundle I/O on several isolates of one process.
