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
write, without writing them.

## Projects

`package:wayfinder/project.dart` is what the `wayfinder` command does with a
project on disk, for a host that embeds it:

```dart
import 'dart:io';

import 'package:wayfinder/project.dart';

Future<void> main() async {
  final project = await WayfinderProject.discover(Directory.current);
  final resolver = WayfinderProfileResolver(
    dataDirectory: WayfinderDataDirectory.resolve(),
  );
  await resolver.resolve(project.root); // wayfinder get
  for (final bundle in project.bundles) {
    final result = await validateWithProfileSources(
      bundle.root,
      resolver: resolver,
    );
    print('${bundle.name}: ${result.gate.wireValue}');
  }
}
```

- `WayfinderProject.discover` finds the nearest `wayfinder.json`, or a
  conventional `knowledge/` directory, and lists its bundles.
- `WayfinderProfileResolver` resolves Git Profile sources. `plan` may fetch
  into the cache but writes nothing in the project; `apply` writes the lock and
  Profile skills, and refuses a plan whose configuration, lock or cache changed
  since; `resolve` is both. `select` reads the lock and the cache for
  validation and never runs Git. `validateWithProfileSources` selects and
  validates; on a cache Wayfinder 0.2 wrote, it first copies the missing
  package files out of the cached mirrors with `restoreCachedPackages`,
  without fetching.
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
  final plan = await adoption.plan(
    AdoptionRequest(
      projectRoot: Directory.current.path,
      profile: ProfileId.parse('bitwild-profile'),
      source: const AdoptionSource(
        git: 'https://github.com/btwld/wayfinder',
        path: 'profiles/bitwild',
      ),
    ),
  );
  for (final file in plan.files) print('${file.action.wireValue} ${file.path}');
  for (final conflict in plan.conflicts) print(conflict);
  if (!plan.applicable) return;
  final result = await adoption.apply(plan);
  print('gate ${result.validation?.gate.wireValue}');
  print(plan.agentInstructions); // for AGENTS.md
}
```

- `plan` writes nothing in the project. It resolves the Profile, which may
  clone or refresh it in the Profile cache (an offline request throws
  `fetch-required` instead), and lists every file `apply` writes with its
  text or digest, every Git fetch, the Profile's source, release and chain,
  the conflicts that stop it, and the gate the adopted bundle will have.
- A request without a ref pins the source's default branch in
  `wayfinder.json` as the commit it resolves to.
- `apply` writes `wayfinder.json`, `wayfinder.lock`, the seeded bundle
  (`index.md`, `log.md` and any seed concepts the host passes), the Profile
  skills and, unless the request says otherwise, a `knowledge/.okf.lock`
  line in `.gitignore`. It refuses a plan with conflicts or whose inputs
  changed, before writing, and undoes earlier steps when one fails, so the
  project never holds a partial bundle. It then validates: `PASS` completes
  adoption.
- It never writes `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or hooks. The plan
  returns the `### Knowledge bundle` block as text for the host to place.
- An existing `wayfinder.json` or `wayfinder.lock`, a bundle directory that
  already holds files (unless the request binds it), and a skill directory
  without Wayfinder's marker are conflicts.
- `KnowledgeSeeds` holds the generic seed text.

[ADR-0020](../../docs/adr/0020-programmatic-adoption.md) records these
decisions.
