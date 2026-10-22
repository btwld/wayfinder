# wayfinder

Core Dart library that validates an OKF bundle with okf, then evaluates the
rules of the Profile package a project selects. It embeds no Profile.
`ProfilePackage` parses a package, and `ProfileValidator` returns a
`ProfileValidationResult` with the OKF report, Profile findings, engine
diagnostics (`EngineDiagnostic`), and the gate derived from them
(`GateState`).

```dart
import 'package:wayfinder/wayfinder.dart';
```

`ProfileValidator.validateLoaded` validates a bundle okf has already loaded,
such as a candidate built in memory, without reading its files again; only the
`path-targets-exist` builtin checks, on disk relative to the bundle root, a
link target okf's graph cannot resolve inside the bundle.
`ProfileProjection.generatedFiles` returns the files `validate --fix` would
write, without writing them. `EffectiveProfile.requiredConceptFields` lists
the frontmatter keys a concept must carry for the gate to pass: those the
Profile's error rules require of every concept, for Bitwild `type`, `title`,
`description` and `status`.

## Projects

`package:wayfinder/project.dart` is what the `wayfinder` command does with a
project on disk, for a host that embeds it. A host passes the project root
it opens, and the library reads nothing above it; the command passes
`searchAncestors: true` to find the project from any directory inside it.

```dart
import 'dart:io';

import 'package:wayfinder/project.dart';

Future<void> main() async {
  final project = await WayfinderProject.discover(Directory('/work/app'));
  final resolver = WayfinderProfileResolver(
    dataDirectory: WayfinderDataDirectory.resolve(),
  );
  await resolver.resolve(project.root); // wayfinder get
  for (final bundle in project.bundles) {
    final result = await validateWithProfileSources(
      bundle.root,
      projectRoot: project.root,
      resolver: resolver,
    );
    print('${bundle.name}: ${result.gate.wireValue}');
  }
}
```

- `WayfinderProject.discover(root)` lists the bundles `root`'s own
  `wayfinder.json` applies to or, without one, its conventional `knowledge/`
  directory, and reads nothing above `root`. With `searchAncestors: true` it
  finds the nearest `wayfinder.json` at or above a directory instead, or the
  nearest `knowledge/` directory below the Git boundary, as the `wayfinder`
  command does from its working directory.
- Without `configPath`, `WayfinderProjectConfig.bind`, the resolver's
  `select` and `restoreCachedPackages`, and `validateWithProfileSources` find
  a bundle's `wayfinder.json` by climbing from the bundle. With `projectRoot`
  they read only directories whose real path is that root or inside it, and
  stop there: a conventional project inside another project reports
  `config-missing` rather than binding the outer project's configuration.
- `WayfinderProfileResolver` resolves Git Profile sources. `plan` may fetch
  into the cache but writes nothing in the project; `apply` writes the lock and
  Profile skills, and refuses a plan whose configuration, lock or cache changed
  since; `resolve` is both. `select` reads the lock and the cache for
  validation and never runs Git. `validateWithProfileSources` selects and
  validates; on a cache Wayfinder 0.2 wrote, it first copies the missing
  package files out of the cached mirrors with `restoreCachedPackages`,
  without fetching.
  `pruneProjectLocks` deletes the `get` locks of project roots that no longer
  exist once they have gone unused for its period (30 days by default),
  reading a lock's note only while the lock is free;
  `WayfinderKnowledgeStore.prune` calls it.
- `ProfileSkills.read(projectRoot, revision)` returns the `SKILL.md` text
  `get` installed for a Profile revision, or null when no installed copy
  holds that revision, the check behind `profile-skill-stale`.
  `ProfileSkills.revisionsOf(selection)` lists the revisions of a selected
  chain's skills.
- `projectWayfinderGraph` is the `graph` command's projection, and
  `wayfinderGraphInput` its Ack query input.
- `WayfinderDataDirectory.resolve`, `GitRunner` and the hardened `runGit`,
  `WayfinderCancellation`, and `WayfinderFileLock`, a `flock` lock that holds
  across processes and isolates and whose momentary `isHeld` probe never makes
  a `tryExclusive` fail, are the injection points and building blocks.
  A host's `GitRunner` applies `wayfinderGitOptions` and
  `wayfinderGitEnvironment`, and on cancellation throws
  `WayfinderException.cancelled()`; `throwIfCancelled` checks between steps.
- Failures are `WayfinderException`s with a stable `code`.

Run all okf bundle I/O of a process on one isolate: okf's bundle lock does
not exclude isolates. [ADR-0018](../../docs/adr/0018-embeddable-libraries.md)
records these decisions.

`WayfinderProjectConfig.toJson`, `WayfinderConfigEncoder` and
`WayfinderConfigEditor` write `wayfinder.json` in its documented layout. The
editor changes a Profile's source and bundles, the project's vocabulary and
its actors, and keeps every field it does not model and every value as
written.

For the command and MCP server, install **wayfinder_cli**:

```sh
dart pub global activate wayfinder_cli
wayfinder validate knowledge
wayfinder mcp knowledge
```

For indexing and search without native setup, use the complete scripted
installation in the [installation guide](../../docs/install.md).
The reusable retrieval library is `wayfinder_embeddings`.

## Adoption

`package:wayfinder/adoption.dart` adopts a Profile in a project, as the
[`adopt-knowledge-bundle`](../../skills/adopt-knowledge-bundle/SKILL.md)
skill does, for a host that sets projects up itself:

```dart
import 'dart:io';

import 'package:wayfinder/adoption.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

Future<void> main() async {
  final adoption = KnowledgeAdoption(
    resolver: WayfinderProfileResolver(
      dataDirectory: WayfinderDataDirectory.resolve(),
    ),
  );
  // The sources the person approved fetching.
  final approved = {'https://github.com/btwld/wayfinder'};
  final plan = await adoption.plan(
    AdoptionRequest(
      projectRoot: Directory.current.path,
      profile: ProfileId.parse('bitwild-profile'),
      source: const AdoptionSource(
        git: 'https://github.com/btwld/wayfinder',
        path: 'profiles/bitwild',
      ),
      allowFetch: (fetch) => approved.contains(fetch.location),
    ),
  );
  for (final file in plan.files) print('${file.action.wireValue} ${file.path}');
  for (final conflict in plan.conflicts) print(conflict);
  if (!plan.applicable) return;
  final result = await adoption.apply(
    plan,
    // The host's own writes, undone with the rest if they fail.
    hostStep: () async => print(plan.agentInstructions), // for AGENTS.md
  );
  print('gate ${result.validation?.gate.wireValue}');
}
```

- `plan` writes nothing in the project. It resolves the Profile, which may
  clone or refresh it in the Profile cache, and lists every file `apply`
  writes with its text or digest, every Git fetch, the Profile's source,
  release and chain, the conflicts that stop it, and the gate the adopted
  bundle will have.
- `allowFetch` decides each clone or refresh before it runs, including one of
  a chain parent's repository that the request never names: no plan can list
  those before it reads the child. A refused fetch throws
  `ProfileFetchRequiredException` (`fetch-required`) naming it; ask the
  person, then plan again with it allowed. An `offline` request reads the
  cache as it is and refuses every fetch.
- A request without a ref pins the source's default branch in
  `wayfinder.json` as the commit it resolves to.
- `apply` writes `wayfinder.json`, `wayfinder.lock`, the seeded bundle
  (`index.md`, `log.md` and any seed concepts the host passes), the Profile
  skills and, unless the request says otherwise or `.gitignore` already lists
  it, a `knowledge/.okf.lock` line in `.gitignore`, then runs `hostStep`. It
  refuses a plan with conflicts or whose inputs changed, before writing. It
  holds the project's `get` lock throughout, so a `get` already running stops
  it with `resolution-busy` before anything is written. It undoes earlier
  steps when one fails or `cancel` fires, so the project never holds a
  partial bundle, and reports a step whose undo failed as `undo-failed`. It
  then validates: `PASS` completes adoption.
- It never writes `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or hooks. The plan
  returns the `### Knowledge bundle` block as text for the host to place.
- An existing `wayfinder.json` or `wayfinder.lock`, a bundle directory that
  already holds files other than `.okf.lock` (unless the request binds it), a
  skill directory without Wayfinder's marker, and one Wayfinder installed
  that the adoption does not install are conflicts. Adoption deletes
  nothing.
- `KnowledgeSeeds` holds the generic seed text.

[ADR-0020](../../docs/adr/0020-programmatic-adoption.md) records these
decisions.
