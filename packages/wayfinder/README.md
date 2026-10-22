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

A project on disk is in `package:wayfinder/project.dart` ([Projects](#projects)),
and writes a Profile governs are in `package:wayfinder/authoring.dart`
([Authoring](#authoring)).

`ProfileValidator.validateLoaded` validates a bundle okf has already loaded,
such as a candidate built in memory, without reading its files again; only the
`path-targets-exist` builtin looks further, for a path target okf's graph
cannot resolve: first in the loaded bundle, so a candidate sees the files it
adds, then on disk relative to the bundle root.
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

## Authoring

`package:wayfinder/authoring.dart` is the write path for a bundle a Profile
governs. `KnowledgeWriter.prepare` builds the candidate one change describes
and judges it in memory; it writes nothing. `KnowledgeWriter.commit` writes
exactly what was judged, under okf's bundle lock:

```dart
import 'package:okf/okf.dart';
import 'package:wayfinder/authoring.dart';
import 'package:wayfinder/project.dart';

Future<void> main() async {
  final writer = KnowledgeWriter(
    resolver: WayfinderProfileResolver(
      dataDirectory: WayfinderDataDirectory.resolve(),
    ),
  );
  final plan = await writer.prepare(
    'knowledge',
    CreateConcept(
      id: OkfConceptId('reporting/pagination-contract'),
      frontmatter: {
        'type': 'Specification',
        'title': 'Pagination contract',
        'description': 'How the renderer splits an export into pages.',
        'status': 'draft',
      },
      body: '# Specification\n\nPages break at section bounds.\n',
    ),
    stamp: const KnowledgeStamp.generated(by: 'claude-code/opus-5'),
    logEntry: const KnowledgeLogEntry(
      action: 'Creation',
      description:
          'Recorded [Pagination contract](/reporting/pagination-contract.md).',
    ),
  );
  for (final finding in plan.introduced) {
    print(finding.toText());
  }
  if (plan.committable) await writer.commit(plan);
}
```

- A `KnowledgeChange` is `CreateConcept`, `UpdateConcept` (a null field
  removes it), `LinkConcepts`, which appends to the concept's `relationships`,
  `DeprecateConcept`, or the `RegenerateIndexes` repair, which writes exactly
  what `validate --fix` writes.
- When the selected Profile generates indexes, a write rewrites only those
  whose generated text it changes; any other index keeps its bytes, stale or
  not. Without such a rule, okf regenerates the changed concept's ancestor
  indexes.
- The root log records the caller's `KnowledgeLogEntry` exactly as given,
  several as `KnowledgeLogEntries` in the order given under one date, okf's
  lifecycle entry (`KnowledgeLog.lifecycle`, the default), or nothing
  (`KnowledgeLog.none`). New entries are inserted as lines in the log's own
  style, so the existing entries keep their bytes.
- A `KnowledgeStamp` records `generated: {by, at}` when the write creates or
  changes content (the body, `title`, `description` or `type`); a verified
  stamp also appends `{by, at}` to `verified`. A change may not set either
  key itself.
- The plan holds the `base` and `candidate` validations, the `diff` of every
  file it writes, and the candidate's Profile findings split into
  `introduced` and `preExisting` by rule id and path. It is `committable` when
  okf accepts the candidate and it introduces no error. Check
  `plan.candidate.gate` to require a passing bundle, and `plan.assessed` to
  require that a Profile judged the write: when none can be selected, the
  plan is judged by OKF alone.
- `commit` throws `KnowledgeWriteRefusedException` (`write-refused`) for a
  plan that is not committable and `KnowledgeStaleWriteException`
  (`write-stale`) when the bundle, or the `wayfinder.json` or `wayfinder.lock`
  its selection came from, changed since `prepare`. Neither writes anything.
  `KnowledgeWriteFailedException` (`write-failed`) reports a bundle that
  cannot be locked, read or written; its `partial` is true only when okf's
  rollback failed too. A plan commits once.
- `prepare` and `commit` take a `WayfinderCancellation`, checked between
  steps; a cancelled commit writes nothing and leaves the plan committable.

`prepare` reads the bundle under okf's shared claim, releases it, and then
runs the Profile assessment once through a `KnowledgeAssessor`, with plain
data and no lock. The default runs it on the calling isolate; another
isolate works too:

```dart
final writer = KnowledgeWriter(
  resolver: resolver,
  assess: (input, cancel) => Isolate.run(input.assess),
);
```

A Profile's rules can be slow, so a host that needs a deadline spawns an
isolate it kills when the deadline passes or `cancel` fires. Run every other
step on the isolate that does the process's other okf bundle I/O. A commit leaves okf's
`.okf.lock` in the bundle, as `validate --fix` does; ignore it in Git.
[ADR-0019](../../docs/adr/0019-profile-aware-writes.md) records these
decisions.

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
