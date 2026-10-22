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
such as a candidate built in memory, and `ProfileProjection.generatedFiles`
returns the files `validate --fix` would write, without writing them.

## Projects

`package:wayfinder/project.dart` is what the `wayfinder` command does with a
project on disk, for a host that embeds it:

```dart
import 'dart:io';

import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

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
  validation and never runs Git.
- `projectWayfinderGraph` is the `graph` command's projection, and
  `wayfinderGraphInput` its Ack query input.
- `WayfinderDataDirectory.resolve`, `GitRunner` and the hardened `runGit`,
  `WayfinderCancellation`, and `WayfinderFileLock`, a `flock` lock that holds
  across processes and isolates, are the injection points and building blocks.
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
