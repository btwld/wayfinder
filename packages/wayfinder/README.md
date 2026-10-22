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
- `ProfileSkills.read(projectRoot, revision)` returns the `SKILL.md` text
  `get` installed for a Profile revision, or null when no installed copy
  holds that revision, the check behind `profile-skill-stale`.
  `ProfileSkills.revisionsOf(selection)` lists the revisions of a selected
  chain's skills.
- `projectWayfinderGraph` is the `graph` command's projection, and
  `wayfinderGraphInput` its Ack query input.
- `WayfinderDataDirectory.resolve`, `GitRunner` and the hardened `runGit`,
  `WayfinderCancellation`, and `WayfinderFileLock`, a `flock` lock that holds
  across processes and isolates, are the injection points and building blocks.
  A host's `GitRunner` applies `wayfinderGitOptions` and
  `wayfinderGitEnvironment`, and on cancellation throws
  `WayfinderException.cancelled()`; `throwIfCancelled` checks between steps.
- Failures are `WayfinderException`s with a stable `code`.

Run all okf bundle I/O of a process on one isolate: okf's bundle lock does
not exclude isolates. [ADR-0018](../../docs/adr/0018-embeddable-libraries.md)
records these decisions.

For the command and MCP server, install **wayfinder_cli**:

```sh
dart pub global activate wayfinder_cli
wayfinder validate knowledge
wayfinder mcp knowledge
```

For indexing and search without native setup, use the complete scripted
installation in the [installation guide](../../docs/install.md).
The reusable retrieval library is `wayfinder_embeddings`.
