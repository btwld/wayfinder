# ADR-0018: Embeddable project and retrieval libraries

- Status: accepted
- Date: 2026-10-22
- Updated: 2026-10-22 (the knowledge store entry and its index lock; a host's fetch policy, and adoption holding the project's `get` lock, with [ADR-0020](0020-programmatic-adoption.md)); 2026-10-22 (only writers hold an index's lock, the knowledge store needs no ObjectBox, the background-index slot uses the helper, and `prune` deletes the `get` locks of removed projects; `tryExclusive` waits out a reader's momentary probe and locks only the file its path names; #110); 2026-10-22 (a host's root bounds discovery and binding; required concept fields and installed skill text are public); 2026-10-22 (a host's process layer runs the hardened Git, whose remote and SSH rules are public; reading a package is bounded; each binding's Profile status, locked-only plans and the source location rule are public, and the fetch policy is all per-source consent needs); 2026-10-22 (the knowledge store's notices are typed, a search can be cancelled, a retained encoder can be released while the snapshots stay, the model cache removes its model, and `forget` deletes lock files and forgets a project root's indexes); 2026-10-22 (a Profile skill read reads the real paths it checked and can be bounded in bytes, a selection names its project root, skill writes and prunes keep to the real roots they checked, and `get` writes no marker it would not read back); 2026-10-22 (a plan can leave Profile skills alone; `status` reports why a lock would change, each chain member's local copy and each skill directory as data; library messages name no command, and diagnostics and resolution failures carry the remedy and data the CLI words); 2026-10-22 (an edit of `wayfinder.json` relocks offline under the project's `get` lock, keeping the locked commits and the skills; the retrieval library's model failures name no command and carry their remedy as data, and the store's `model-missing` and `model-invalid` each imply that one remedy)
- Scope: the public Dart entries, what a host injects, Wayfinder's lock files, and the CLI's role; no Profile rule, and no change to the command's results beyond a Profile skill marker that is unreadable, not a regular file or over 64 KiB counting as no marker, and `get` refusing a file or link where a skill directory goes
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
It confines the marker and `SKILL.md` by their real paths and reads those
paths, so a symbolic link retargeted after the check cannot move the read
outside the project. It opens each only when it is a regular file, checked
without following links just before the open, and drops a text whose real
path holds a link once read or whose marker has become a link. Dart opens a
file only by following its path, and an open of a named pipe waits for a
writer, so two swaps in the moment between that check and the open remain
out of reach: a link put in place and removed again before the read ends,
whose target the read returns, and a named pipe, which holds the read. A
host that must exclude them keeps writers out of the project while it
reads.
A host bounds what a huge file costs with `maxBytes`: the read stops one
byte past it, and a longer file is cut at the last UTF-8 character boundary
within it and reported `truncated` rather than refused, since a host that
shows a skill can still show its start and say it was cut. A marker is read
up to 64 KiB and only when it is a regular file when checked, so a named
pipe or a huge file marks no revision instead of holding the read. Only a
release tens of thousands of characters long would make Wayfinder's own
marker larger, and `get` refuses to install such a skill rather than write
a marker it would not read back.
`SelectedProfile.projectRoot` names the directory of the `wayfinder.json`
that bound the selection, where its skills are installed and its
`profile-skill-stale` notes looked, so a host passes it to `read` rather
than derive it from the configuration's path; the constructor refuses a
root that is not the configuration's absolute directory. `get` installs and
prunes skills the same way, under the real path of each skill root it
confined to the project. It checks every directory's marker before writing
any, and each again just before moving it aside, so it never replaces a
directory without one; a directory that appears in between stops the write
after the roots before it were replaced.
`package:wayfinder_embeddings/knowledge_store.dart` holds the index
lifecycle: `WayfinderKnowledgeStore` reports a bundle's index `status`,
indexes it with progress events and cancellation, searches one bundle or a
project's bundles ranked together, also cancellably, and `forget`s and
`prune`s indexes; `forgetProjectRoot` forgets every bundle of a project root
that may be gone. Its results are typed citations and typed notices with the
CLI's JSON and Markdown renderings; a notice has a stable code, its sentence
and the paths it concerns, so a host never parses its text. It exports the
Ack inputs of host search tools, `wayfinderSearchInput` and
`knowledgeMetadataFilterInput`. A host that retains the store's encoder can
release it, at once or after an idle period, without losing the parsed
snapshots or disposing the store. `package:wayfinder_embeddings/testing.dart`
has `DeterministicTestEmbedder`, whose word-hash vectors test mechanisms
without a model, as [ADR-0017](0017-dense-only-retrieval.md) allows. The
core depends on none of `wayfinder_embeddings`, ObjectBox, llamadart or
analyzer.

**The host owns its resources.** Neither library downloads, prompts, loads
a native library from disk or resolves files next to the executable, except
the embedding model, which the retrieval library downloads only when a host
calls `EmbeddingModelCache.provision`, and deletes only when it calls
`EmbeddingModelCache.remove` ([ADR-0010](0010-wayfinder-cli.md)). A host
injects the data directory (`WayfinderDataDirectory.resolve()` by default),
a `GitRunner` (`runGit` by default) or only the `GitProcessStarter` that
`runGit` starts Git with, a `WayfinderCancellation`, and the validator's okf
loader and graph builder. The knowledge store also takes a
`WayfinderEncoderProvider`, whose identity names the index without opening a
model, such as `LocalModelEncoderProvider` over a model file the host
located and the store verifies before loading. The store keeps indexes as
plain files and needs no database library
([ADR-0010](0010-wayfinder-cli.md)). The CLI's `native_runtime.dart` is that
host: it finds the model in its bundle or in the package during
development. Failures are
`WayfinderException`s with a stable `code` and a sentence that names no
command; the CLI adds what to run, such as `Run wayfinder index <bundle>.`
The same holds for the diagnostics selection and `status` report: the
sentence says what happened, and `EngineDiagnostic.remedy`, like
`WayfinderProfileResolutionException.remedy`, names as data what fixes it,
such as resolving the Profiles again or selecting new revisions. The CLI
words it (`Run wayfinder get.`) into the result it prints
(`ProfileValidationResult.withDiagnosticMessages`), so its output keeps the
advice; the result's JSON, text and SARIF do not carry the remedy, because
the guide's diagnostic has a message and a location only. A failure whose
remedy depends on what it found is typed and carries that:
`ProfileSkillDirectoriesException` the skill directories `get` may not
replace, `ProfileResolutionBusyException` the busy project or source,
`ProfileLockChangeRequiredException` its `ProfileLockChange`. The retrieval
library does the same: `EmbeddingModelSpec.verify` reports a missing or
mismatched model with a sentence and an `EmbeddingModelRemedy` that says a
verified copy of the pinned model fixes it, and the CLI says to reinstall
its bundle or, in a source checkout, to prepare the model. The knowledge
store's `LocalModelEncoderProvider` reports the two as the codes
`model-missing` and `model-invalid`, each with that one remedy, so a host
of the store keys its wording on the code. A diagnostic
for a missing or stale lock carries its `ProfileLockChangeKind`
(`EngineDiagnostic.lockChange`), so the CLI keeps its own wording of a lock
an edit of `wayfinder.json` made stale. A host then words its own remedy,
such as a consent prompt, without parsing a message or running Git.

**A host's root bounds the project.** A host knows the workspace or
worktree it opens, and a `wayfinder.json` or Git boundary above it, such as
one in a home directory, is not that project's. `WayfinderProject.discover`
therefore reads nothing above the root it is given: the bundles are those
the root's own `wayfinder.json` applies to, or its `knowledge/` directory.
Binding takes the same bound: with `projectRoot`, the search for a bundle's
`wayfinder.json` climbs the same directories as without it but reads only
those whose real path is that root or inside it, and stops there, so a
bundle with none there reports `config-missing`. Adoption's closing
validation binds within the root it adopted, and `KnowledgeWriter.prepare`
takes the same `projectRoot`. The command still finds the project from any
directory inside it by asking for its search of ancestors
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
(`GitResult`), because skill files are blobs, and bounded: a command that
writes more than `maxOutputBytes` of stdout (64 MiB by default) is stopped
with `git-output-too-large` rather than return a cut blob, and only the last
64 KiB of stderr are kept. Once a command exits, `runGit` reads its stdout to
its end, and its stderr until it closes or a second passes without any,
because a helper it left running, such as an SSH connection master, can hold
stderr open. A pause in stdout never ends the read, since a busy isolate or a
host's process layer can delay its last bytes: both streams must end within
ten seconds of the exit (or the command's timeout, when shorter), a stdout
still open then fails with `git-output-incomplete`, a stderr still being
written is cut, and either way `GitProcess.kill` is asked to stop the helpers.
A result therefore holds all of stdout or none of it. A host whose process
layer must start every process, for its search path, sandbox or tree kill,
passes a `GitProcessStarter` to `runGit` and keeps all of this; the starter
receives the hardened arguments and the whole environment, and its
`GitProcess.kill` stops the command's tree. A host that writes its own runner
applies the same through the public rules: `wayfinderGitOptions`,
`wayfinderGitEnvironment`, `gitMayReachRemote` (the subcommands of
`wayfinderGitRemoteSubcommands`, found by `gitSubcommand` past Git's global
options), `wayfinderSshCommand` (the SSH command Git would choose, in batch
mode) and `wayfinderConfiguredSshCommand` (the `core.sshCommand` lookup). The
remote rule chooses when to look SSH up; it is no sandbox, since an alias can
reach a remote under any name.

**Resolution is plan, then apply.** `plan` resolves and composes every chain
and may clone or refresh a source in the cache, but writes nothing in the
project. A host's `ProfileFetchPolicy` decides each clone or refresh just
before it runs, including one of a chain parent's source that the
configuration never names; a refused fetch throws
`ProfileFetchRequiredException` (`fetch-required`), which names it, so the
host can ask the person and plan again. The policy is all a host needs for
per-source consent: every Git command a resolution runs that can reach the
network, a mirror's `clone` or `remote update`, follows the policy's yes for
the `ProfileFetch.location` it reaches, and every other command reads a mirror
already in the cache. That location is
`WayfinderProfileSource.locationOf(git, projectRoot:)`: a URL, `scp`-style
address or absolute path as written, a relative path joined to the project
root. It names the cache directory and mirror lock too, so a consent gate
compares it with the locations of the sources a person approved and needs no
wrapper around Git. `plan(lockedOnly: true)` resolves exactly the commits
`wayfinder.lock` pins, as a host does to bring a project's locked Profiles
onto a machine: it fetches a source only when its mirror is missing or lacks
the locked commit, never re-resolves a ref, so the lock's commits stay as
written, and keeps the lock's bytes. When the lock as written would change,
because it is missing or stale, lacks a binding's chain or holds a package no
chain reaches, it throws `lock-change-required` before any Git command; a
package whose own file disagrees with the lock, which only an edited lock has,
is refused once read. The refusal's `ProfileLockChange` says why as data: its
kind, the binding and the lock entries it concerns. `plan(skills: false)`
leaves Profile skills alone, as a host does to fill the cache before it asks
about the protected paths a skill install writes: it reads no skill file,
refuses no skill directory, its apply writes and deletes none, and it reports
each skill directory's state rather than refusing an unmarked one.
`apply` writes the lock and skills and refuses a plan
whose configuration, lock or cached package files changed since
(`resolution-stale`). `resolve` is both under one hold of the project's lock.

**An edit of `wayfinder.json` relocks offline.** The lock's hash covers the
whole configuration, actors and project vocabulary included, so a host that
registers an actor makes the lock stale although its Profiles stay the same.
`relock` applies the host's edit to the configuration's text and writes the
lock for the result under one hold of the project's `get` lock, so no `get`,
apply or adoption runs meanwhile and a plan made before it no longer
applies. It keeps exactly the commits the lock pins: it runs no Git, so it
fetches nothing and resolves no ref, and it reads each chain from the
Profile cache and composes it as `select` does. It writes and deletes no
skill. Before writing anything it refuses, as `lock-change-required` with
the `ProfileLockChange`, an edit after which the lock does not pin exactly
each binding's chain at its source, since only a resolution that may fetch
can lock that, and it refuses what selection would report, such as a
package the cache lacks. It writes the configuration, then the lock, each
through a temporary file, and gives a file it wrote its bytes back when a
later write fails. The lock it writes is the one `get` writes for the same
commits, so it needs no guide §9 entry and no format bump.
`WayfinderConfigEditor.encode(minimal: true)` makes the edit itself change
only the members it touches, keeping the rest of the file's bytes.
A plan keeps the package file of each package it reads, so `select`, the
selection validation uses, reads files only and never runs Git. A cache
Wayfinder 0.2 wrote has the mirrors but no package files: when `select` finds
no Profile, `validateWithProfileSources` copies the missing files out of the
existing mirrors with `git show` (`restoreCachedPackages`), never fetching,
and selects again. `status` reports, offline and without Git, where each
binding stands as `select` would find it, with a stable state: `resolved`,
`lock-missing`, `lock-stale`, `cache-missing`, `package-invalid`,
`package-unsupported`, `package-timeout` or `composition-failed`, the locked
chain, the members missing from the cache, and the diagnostic `select`
reports. The diagnostics keep their codes, so the command's output is
unchanged; a host reads the state instead of telling `profile-unresolved`
messages apart. It also reports, from one read of the lock and without Git,
what a consent gate names: each chain member's local copy (whether its
source's mirror and its package file are in the cache, since a locked-only
plan contacts a source only to clone a missing mirror or refresh one that
lacks the locked commit), the state of each skill directory a resolved chain
installs into (`current`, `missing`, `stale`, `unmarked` or `outside`, as
`ProfileSkills.inspect` reads it), and the `ProfileLockChange` a locked-only
plan would refuse with, a lock entry no chain reaches included. `get` refuses
anything that occupies a skill directory without the Profile's marker, a file
or link included, before it writes the lock.
A Profile skill marker that cannot be read counts as no
marker, so its skill is `profile-skill-stale` and `get` leaves the directory
alone. Without that, `status` would meet the failed read as a file it cannot
read and report `cache-missing`.

**Reading a package is bounded.** Parsing a package runs its rules' `tests`,
and so its `pattern`s, on Dart's backtracking regular-expression engine,
which nothing on the parsing isolate can interrupt. The resolver therefore
reads every package, in a plan or a selection, with
`ProfilePackage.parseWithin`: the parse runs on an isolate of its own, which
is killed once it runs past the resolver's `packageTimeout` (ten seconds),
and the package is refused as `wayfinder/profile-timeout`, naming the rule
whose tests were running (guide §5.6, [ADR-0015](0015-profile-rule-catalogs.md)).
A parse that stops on another error, such as a stack overflow in a rule's
tests, is refused as `profile-invalid` naming that error; it never runs again
unbounded on the caller, which only parses when no isolate can be started. The
isolate holds no lock, so killing it leaves the mirror free. A package that
passed is read again on the calling isolate without its tests. Every read runs
the tests: no verdict is cached by the package's digest, because a cached
verdict could outlive the engine that reached it. Validating a bundle's
content runs the same patterns and is not bounded by the engine; a host that
validates content it does not control runs that where it can stop it.

**Wayfinder's lock files use `WayfinderFileLock`.** It is `flock(2)` on a
descriptor of its own through `dart:ffi` on POSIX, and `RandomAccessFile.lock`
on Windows, whose `LockFileEx` lock belongs to its handle. Both hold across
processes and across the isolates of one process, and closing another
descriptor never releases them. A lock file stays in place on release.

| Resource | Lock file under the data directory | Mode | On contention |
| --- | --- | --- | --- |
| A Profile source's mirror, while a plan clones, refreshes or reads it | `profiles/<sha256(location)>.lock` | exclusive, waits up to 120 s; restoring package files never waits | waits, then `resolution-busy`; restoring skips the mirror |
| A project's `get`, its adoption ([ADR-0020](0020-programmatic-adoption.md)) from the check step until every step has finished or been undone, or its relock | `projects/<sha256(root)>.get.lock` | exclusive, never waits | `resolution-busy` |
| A bundle's index for one configuration, while `index`, `forget` or `forgetProjectRoot` runs, and while `prune` deletes it | `indexes/bundles/<bundle key>/<configuration key>/writer.lock` | exclusive, never waits; searches and `status` never hold it, and probe it with `isHeld` to report a refresh | `index-busy` |
| The machine's one background index (`wayfinder index --detach`) | `background-index.lock` | exclusive, never waits | the CLI reports `running` and starts nothing |

"Never waits" means never waiting for a holder. `isHeld` takes a shared lock
on a descriptor of its own and releases it at once, so a probe holds the file
for an instant while a holder keeps it for its whole operation: `tryExclusive`
tries a refused lock again for up to 100 ms before it reports the holder, so a
search's or a prune's probe never makes a writer busy. A plan holds one
mirror's lock at a time, so two plans never deadlock. The
project lock records the project root it protects, so a later cleanup can
tell which lock belongs to a root that no longer exists. Read that note only
while the lock is free (`isHeld` is false): on Windows the lock is a mandatory
byte-range lock, so no other handle reads a held lock file. No lock file is
kept for compatibility with an earlier release: `flock` and `fcntl` locks do
not exclude each other, so a background index of an earlier release does not
exclude one of this release. Only writers hold an index's lock: searches read
immutable generations without it, so a search during an index keeps working
([ADR-0010](0010-wayfinder-cli.md)). The writer lock records the bundle root,
which also lets `forgetProjectRoot` find the bundles of a project that is
gone; a held lock whose note it cannot read, as on Windows, makes it
`index-busy` rather than skip an index that may be the project's. Its
modification time is the index's last use: a writer writes the note, and a
search or `status` sets the time. `forget` and `forgetProjectRoot`
delete the index's pointer and generations while holding the lock, then the
lock file and the directories that leaves empty, since a host forgets an
index it means to be gone, such as a removed worktree's. `prune` deletes the
pointer and generations the same way, but a lock file, an index's or a
removed project's `get` lock, only once it has gone unused for the prune's
period, so no operation is opening it. Either keeps a lock file while
anything else is left beside it, such as a generation a reader on Windows
has open, so a later prune still finds the index. A lock file is deleted
while held, on Windows right after its release. An operation that opened it
just before it went still never holds a deleted file: once
`WayfinderFileLock` has the lock, it checks that the path still names the
file it locked (the same device and inode on POSIX; Windows deletes no open
file) and otherwise opens the path again, so two operations never hold
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

A host keeps one process layer and one consent gate without copying
Wayfinder's: its starter runs the hardened Git, its `ProfileFetchPolicy`
decides each source, a locked-only plan downloads what a lock pins, without
touching skills when the host asks, and `status` names offline each
binding's state, the sources a download contacts and the skill directories
an install writes. A Profile package whose tests
stall fails `get` and selection with `profile-timeout` instead of holding
them, at the cost of one short-lived isolate per package read.

Lock files and package files accumulate in the data directory, which stays
derived and removable; `prune` removes the indexes of bundles that no longer
exist at once, and their lock files, like the `get` locks of projects that no
longer exist, once those go unused for its period, by default 30 days. A holder also checks that its lock file still exists, so
the only remaining race needs an operation to open a lock file unused for
that long in the moment `prune` deletes it, and another to start on that
index meanwhile; it costs at worst a rebuild, and the publishing operation
that loses reports `index-busy`. A `prune` with a short period widens that
window, and so does `forget`, which deletes lock files at once: a host
forgets indexes nothing uses any more, such as a removed worktree's. `flock`
is only as strong as the filesystem: keep the data directory on a local
disk.

## Reconsider when

okf's bundle lock excludes isolates, Dart gains a per-descriptor file lock, or
a host needs okf bundle I/O on several isolates of one process.
