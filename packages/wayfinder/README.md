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
- `status(root)` says, offline and without Git, where each binding's Profile
  stands as `select` would find it: a `ProfileBindingState` (`resolved`,
  `lock-missing`, `lock-stale`, `cache-missing`, `package-invalid`,
  `package-unsupported`, `package-timeout` or `composition-failed`), the
  locked chain, the members missing from the cache, and the diagnostic
  `select` reports. Beside them it reports as data what a consent gate
  names:
  - `copies`, one `ProfileLocalCopy` per chain member: its source's
    `location` and whether its mirror (`hasMirror`) and package file
    (`hasPackage`) are in the Profile cache. A locked-only plan contacts a
    source only to clone a missing mirror, or to refresh one that lacks the
    locked commit;
  - `skillDirectories`, each `.claude/skills/<id>` and `.agents/skills/<id>`
    a resolved chain's skills install into, with a
    `ProfileSkillDirectoryState`: `current`, `missing`, `stale` (Wayfinder's
    marker at another revision), `unmarked` (something without the Profile's
    marker, which `get` refuses to replace) or `outside` (a skill root a
    symbolic link places outside the project). `ProfileSkills.inspect`
    reads the same for one revision;
  - `lockChange`, a `ProfileLockChange` for a lock that is missing or
    stale: its `kind` (`lock-missing`, `configuration-changed`,
    `chain-missing`, `source-changed`, `package-changed` or
    `packages-unreached`), the binding and lock entries it concerns, and the
    reason. The status's own `lockChange` is what a locked-only plan would
    refuse before running Git, a lock entry no chain reaches included.
- `plan(root, lockedOnly: true)` resolves exactly the commits
  `wayfinder.lock` pins and leaves the lock as written: it fetches a source
  only when its mirror lacks the locked commit and never re-resolves a ref,
  so the lock's commits stay as written. A lock that would change, because
  it is missing or stale or does not hold each binding's chain, fails with
  `lock-change-required` before any Git command, and the
  `ProfileLockChangeRequiredException` carries that `ProfileLockChange`.
  Apply the plan to reinstall the locked Profile skills.
- `plan(root, skills: false)` leaves Profile skills alone, as a host does to
  fill the Profile cache without touching `.claude/skills` or
  `.agents/skills`: it reads no skill file, refuses no skill directory, and
  its apply writes and deletes none. The plan's `skillDirectories` reports
  every skill directory's state, unmarked and outside ones included, which a
  plan with skills refuses with `ProfileSkillDirectoriesException`.
- `allowFetch`, a `ProfileFetchPolicy`, decides each clone or refresh just
  before it runs, and every Git command that can reach the network follows
  its yes for that `ProfileFetch.location`, so it is all a consent gate
  needs. `WayfinderProfileSource.locationOf(git, projectRoot:)` is the
  location the resolver gives a source: compare it with the sources a person
  approved.
- Reading a Profile package runs its rules' `tests`, so the resolver reads
  each one on an isolate of its own and refuses one that runs past
  `packageTimeout` (ten seconds) as `wayfinder/profile-timeout`, and one
  whose parse stops on an error, such as a stack overflow, as
  `wayfinder/profile-invalid`; `ProfilePackage.parseWithin` is that bounded
  parse.
- `ProfileSkills.read(projectRoot, revision)` returns the `SKILL.md` text
  `get` installed for a Profile revision as a `ProfileSkillText`, or null
  when no installed copy holds that revision, the check behind
  `profile-skill-stale`. It reads the real path it confined to the project,
  so a symbolic link changed after the check does not move the read, drops a
  file a link replaced meanwhile, and checks that each file is a regular file
  just before opening it. Dart cannot open a file without following a link
  or waiting on a named pipe, so a swap in that last moment is out of its
  reach; a host that must exclude it keeps writers out while it reads.
  With `maxBytes` it reads no more than one byte past that limit, and a
  longer file comes back cut at the last UTF-8 character boundary within it,
  with `truncated` set. `ProfileSkills.revisionsOf(selection)` lists the
  revisions of a selected chain's skills, and `selection.projectRoot` is the
  directory of the `wayfinder.json` that bound it, where they are installed.
  Inside the loop of the example above, with `package:wayfinder/wayfinder.dart`
  imported for `SelectedProfile`:

  ```dart
  final selection = await resolver.select(
    bundle.root,
    projectRoot: project.root,
  );
  if (selection case SelectedProfile(:final projectRoot?)) {
    for (final revision in ProfileSkills.revisionsOf(selection)) {
      final skill = await ProfileSkills.read(
        projectRoot,
        revision,
        maxBytes: 16 * 1024,
      );
      print('${revision.id}: ${skill?.truncated}');
    }
  }
  ```
- `projectWayfinderGraph` is the `graph` command's projection, and
  `wayfinderGraphInput` its Ack query input.
- `WayfinderDataDirectory.resolve`, `GitRunner` and the hardened `runGit`,
  `WayfinderCancellation`, and `WayfinderFileLock`, a `flock` lock that holds
  across processes and isolates and whose momentary `isHeld` probe never makes
  a `tryExclusive` fail, are the injection points and building blocks.
  `runGit` returns all of a command's stdout as bytes, up to
  `maxOutputBytes` (64 MiB), or fails; it never returns part of it. It starts
  Git through `start`, a `GitProcessStarter`: a host whose process layer must
  start every process passes its own and keeps the rest of the hardening. A
  host's own `GitRunner` applies `wayfinderGitOptions`,
  `wayfinderGitEnvironment` and `wayfinderConfiguredSshCommand`, with
  `gitMayReachRemote` and `wayfinderSshCommand` for the rules they follow,
  and on cancellation throws `WayfinderException.cancelled()`;
  `throwIfCancelled` checks between steps.
- Failures are `WayfinderException`s with a stable `code` and a message
  that says what happened and names no command; the `wayfinder` command adds
  what to run. A selection's or status's diagnostic carries a
  `DiagnosticRemedy` (`remedy`) when resolving the Profiles again fixes it,
  as `WayfinderProfileResolutionException.remedy` does when selecting new
  revisions would, and the `ProfileLockChangeKind` (`lockChange`) of a lock
  that is missing or stale; `ProfileValidationResult.withDiagnosticMessages`
  words remedies into a result before a host renders it. Typed failures
  carry their data: `ProfileSkillDirectoriesException` the skill
  directories `get` may not replace, `ProfileResolutionBusyException` the
  project or source that is busy, `ProfileLockChangeRequiredException` its
  `ProfileLockChange`, and `ProfileFetchRequiredException` its fetch.

A host that brings a project's locked Profiles onto a machine with a
person's consent reads the status, asks about the sources a download
contacts, fills the Profile cache from the lock alone, and only then asks
about the skill directories it would write:

```dart
final status = await resolver.status(project.root);
if (status.lockChange == null &&
    status.bindings.any(
      (binding) => binding.state == ProfileBindingState.cacheMissing,
    )) {
  // Name the sources whose mirror the cache lacks: the ones a clone contacts.
  final toFetch = {
    for (final binding in status.bindings)
      for (final copy in binding.copies)
        if (!copy.hasMirror) copy.location,
  };
  final approved = await askThePerson(toFetch);
  final plan = await resolver.plan(
    project.root,
    lockedOnly: true,
    skills: false,
    allowFetch: (fetch) => approved.contains(fetch.location),
  );
  await resolver.apply(plan); // Writes nothing in the project.
}
// The protected paths a get would write, or refuses to.
final skills = [
  for (final binding in (await resolver.status(project.root)).bindings)
    for (final directory in binding.skillDirectories)
      if (directory.state != ProfileSkillDirectoryState.current) directory,
];
```

A refused fetch throws `ProfileFetchRequiredException` (`fetch-required`),
which names the source to ask about before planning again, as for a mirror
that lacks the locked commit. With the person's agreement to those skill
directories, a locked-only plan with skills, which now fetches nothing,
installs them.

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
- Without a `selection`, `prepare` binds the bundle through the nearest
  `wayfinder.json` above it, towards the filesystem root by default. A host
  passes the project root it opens as `projectRoot`, and binding then reads
  nothing above it, as `WayfinderProjectConfig.bind` does.

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
