# ADR-0018: Embeddable project and retrieval libraries

- Status: accepted
- Date: 2026-10-22
- Updated: 2026-10-22 (fetch policy, root bounds and public skill/concept metadata)
- Scope: public Dart entries, host resources, locking and CLI ownership; no Profile rule
- Builds on: [0010](0010-wayfinder-cli.md), [0011](0011-wayfinder-mcp.md), [0012](0012-wayfinder-graph-projection.md)
- Amendments incorporated: [0021](0021-graph-projection-in-project-library.md), [0023](0023-host-resolution-seams.md), [0024](0024-generator-revision-and-offline-relock.md), [0026](0026-model-cache-and-source-paths.md); store lifecycle in [0022](0022-plain-file-index-generations.md)

## Context and decision

IDE and agent hosts need CLI behavior in process. Move reusable discovery,
resolution, validation and graph logic out of CLI internals into public libraries.
The CLI owns arguments, rendering, MCP and installed-command operations.

`package:wayfinder/wayfinder.dart` exposes validation/projection;
`project.dart` owns projects, Profiles, graph, cancellation, Git and file locks.
The graph uses `wayfinderLinkFields` (`relationships`); neither graph nor retrieval
embeds a Profile's conventions. `knowledge_store.dart` in the retrieval package
owns indexing/search. Core Wayfinder depends on no native retrieval stack.
Hosts inject data directories, Git, loaders, encoders and cancellation; libraries
never prompt or implicitly download/load native resources. Host `projectRoot`
bounds discovery, binding, adoption validation and writes. CLI ancestor discovery
remains available. Typed failures expose stable codes and remedy data.

Wayfinder locks are per descriptor (`flock` on POSIX; byte ranges on Windows).
Mirror resolution waits up to 120 seconds; project `get`/adoption never waits.
Only one mirror lock is held at once. Read a project lock's root note only while
free: Windows forbids another handle reading a held lock. Keep data on local disk.
**All okf bundle I/O in one process stays on one isolate:** okf's `fcntl` lock
cannot exclude isolates, and closing another descriptor can release it. Only
in-memory assessment may move to another isolate.

## Host controls (0023, 2026-10-24)

Package parsing normally uses a killable isolate with a ten-second timeout and
`profile-timeout`; if isolate spawning is unavailable, synchronous parsing has
no timeout. Bundle-rule evaluation is also unbounded by default. Hosts requiring
hard bounds must isolate the work themselves; see the [parser contract](../../skills/create-profile/references/package-format.md#tests).

Status is structured data. Locked-only plans reject lock changes before Git;
cache-only plans can omit skill writes. Skill reads check the locked marker,
regular-file real paths and optional byte bound; skill replacement rejects
unmarked directories, including races, but earlier replacements are not undone.
Git drops inherited `GIT_*` routing variables while retaining config/SSH choices,
disables prompts, bounds processes and refreshes only the approved `origin`.

## Consequences

Hosts reuse behavior without importing CLI internals, but own resource lifecycle,
fetch consent and serialization. Cancellation is cooperative between steps, not
inside okf transactions. A complete cache validates without spawning Git; old
caches may need package restoration. Git environment options stripped by hardening
must move to Git configuration. Public API details live in the
[core package guide](../../packages/wayfinder/README.md#projects).
Reconsider the isolate rule if okf gains locks that exclude isolates.
