# 0.3.0 (unreleased)

- New `package:wayfinder/project.dart`, moved from `wayfinder_cli`'s private
  sources so a host can embed what the command does (ADR-0018):
  `WayfinderProject.discover` and `ProjectBundle`;
  `WayfinderProfileResolver`, now with a required `dataDirectory`, and its
  lock types; `validateWithProfileSources`, now with a required `resolver`;
  `ProfileSkills`; `projectWayfinderGraph`, `wayfinderLinkFields` and the Ack
  `wayfinderGraphInput`; `WayfinderDataDirectory.resolve`; and
  `WayfinderException`, which gains a stable `code` beside its message and a
  `WayfinderException.cancelled()` constructor.
- `WayfinderProject.discover(root)` reads nothing above `root`: the bundles
  are those `root`'s own `wayfinder.json` applies to or, without one, its
  `knowledge/` directory. `searchAncestors: true` is the command's search
  instead, the nearest `wayfinder.json` at or above the directory or the
  nearest `knowledge/` directory below the Git boundary; the CLI and MCP
  server pass it, so their output is unchanged. A directory that does not
  exist or cannot be read is `bundles-missing`, not a `FileSystemException`.
- `WayfinderProjectConfig.bind`, the resolver's `select` and
  `restoreCachedPackages`, and `validateWithProfileSources` take
  `projectRoot`, which stops their search for a bundle's `wayfinder.json` at
  that directory: the search climbs from the bundle's parent as before but
  reads only directories whose real path is `projectRoot` or inside it, so a
  bundle with none there reports `config-missing`. Without it they search
  towards the filesystem root as before.
- `EffectiveProfile.requiredConceptFields` lists the frontmatter keys every
  concept must carry for the gate to pass: those an error rule's
  `frontmatter` schema check requires unconditionally, in rule order. For
  Bitwild these are `type`, `title`, `description` and `status`. It
  combines `requiredRootProperties`, which a `SchemaCheck`'s `schema` now
  lists for its own rule.
- `ProfileSkills.read` returns the `SKILL.md` `get` installed for a skill
  revision, as a `ProfileSkillText`, from a directory whose marker holds that
  revision and that no symbolic link places outside the project, or null. It
  reads the marker and `SKILL.md` through the real paths it confined to the
  project, so a link retargeted after the check does not move the read,
  opens each only when it is a regular file just before the open, and
  returns the text only when its real path still holds no link afterwards
  and its marker is not a link. A link or named pipe swapped in between that
  last check and the open stays out of its reach, since Dart cannot open a
  file without following a link or waiting on a pipe.
  It takes no lock and reads the marker again after the text, so a
  concurrent `get` never makes it return another revision's text. With
  `maxBytes` it reads at most one byte past the limit and cuts a longer file
  at the last UTF-8 character boundary within it, setting `truncated`; a
  `SKILL.md` that is not UTF-8 text counts as unreadable.
  `ProfileSkills.revisionsOf` lists the skill revisions of a
  `SelectedProfile`'s chain.
- `SelectedProfile.projectRoot` is the directory of the `wayfinder.json`
  that bound the selection, where `get` installed its skills, so a host
  passes it to `ProfileSkills.read` instead of deriving it from `config`.
  It is null for a selection built by hand that names none, and the
  constructor refuses one that is not the absolute directory of `config`.
- `ProfileSkills.write` and `ProfileSkills.prune` work under the real path
  of each skill root that `escaping` confined to the project, so a symbolic
  link changed after that check does not move a write or a delete. `write`
  refuses to replace a directory without the marker for its id: it checks
  every root before writing any, and each again just before moving it, where
  a directory that appeared meanwhile stops it after the roots before it
  were replaced. A marker that is not a regular file when checked or is
  larger than 64 KiB marks no revision and is never read whole; `write`
  refuses, and `get` fails before writing anything for, a revision whose
  release would make its marker larger.
- The resolver splits `get` into `plan`, which may fetch into the cache but
  writes nothing in the project, and `apply`, which writes it and throws
  `resolution-stale` when the configuration, lock or cache changed since.
  `resolve` runs both. `select` reads the lock and the package files a plan
  kept under `profiles/packages/`, and never runs Git. A cache Wayfinder 0.2
  wrote has no package files: `restoreCachedPackages` copies them out of the
  cached mirrors with `git show`, never fetching, and
  `validateWithProfileSources` does so when `select` finds no Profile, so
  such a cache validates as before. `WayfinderProfileResolutionException`
  carries its `DiagnosticCode` as `diagnostic` and that code's value as
  `code`.
- `GitRunner` returns `GitResult`, whose `stdout` holds bytes, and takes a
  `WayfinderCancellation` in place of `binary`. The default `runGit` drops
  the `GIT_*` variables other than `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`,
  `GIT_CONFIG_NOSYSTEM`, `GIT_SSH_COMMAND`, `GIT_SSH` and `GIT_SSH_VARIANT`;
  never prompts; runs the SSH command Git would choose, including
  `core.sshCommand`, with `-o BatchMode=yes` when it is OpenSSH; skips Git LFS
  downloads; disables hooks, the filesystem monitor and the `ext::` transport;
  and kills a command with its children once it writes nothing for `timeout`
  (five minutes) or on cancellation (`git-timeout`, `cancelled`). The
  resolver clones with `--progress`, so a long clone keeps running.
  `wayfinderGitOptions` and `wayfinderGitEnvironment` let a host's runner
  apply the same, and `throwIfCancelled` checks a cancellation.
- `WayfinderFileLock` is an exclusive lock that holds across processes and
  across the isolates of one process: `flock(2)` through `dart:ffi` on POSIX,
  `RandomAccessFile.lock` on Windows. A plan holds
  `profiles/<sha256(location)>.lock` while it clones, refreshes or reads a
  source's mirror, waiting up to 120 seconds; `apply` and `resolve` hold
  `projects/<sha256(root)>.get.lock` and throw `resolution-busy` while another
  holder has it. The project lock records its root; on Windows, read that
  note only while the lock is free.
- `ProfileValidator.validateLoaded` validates an `OkfBundleLoadResult`
  without reading its bundle files again; only `path-targets-exist` still
  checks, on disk relative to the bundle root, a link target okf's graph
  cannot resolve inside the bundle. `ProfileProjection.generatedFiles` returns
  the files `validate --fix` writes. `validate` delegates to both; its results
  are unchanged.
- `wayfinder` depends on `crypto` and `ffi`.
- `WayfinderProjectConfig.toJson` and `encode`, `WayfinderConfigEncoder`, and
  `WayfinderConfigEditor`, which edits a `wayfinder.json` document's Profile
  sources, bundles, vocabulary and actors and keeps every field it does not
  model. `WayfinderVocabulary` names the vocabulary list an edit changes, and
  `WayfinderProfileBinding.explicitBundlePath` writes a bundle path in the
  `./` form. The definitions, actors, sources, bindings and
  `ProjectVocabulary` gain `toJson`.
- `ProfileResolutionPlan.fetches` lists each clone or refresh a plan made,
  as `ProfileFetch` values, and its JSON gains `fetches`. `plan` and
  `resolve` take a `ProfileFetchPolicy`, `allowFetch`, that decides each
  fetch before it runs, including one of a chain parent's source the
  configuration never names. A refused fetch throws
  `ProfileFetchRequiredException` (`fetch-required`), which carries the
  `ProfileFetch`.
- `ProfileSkills.markerText` is the text of a skill directory's
  `.wayfinder-profile` marker.
- New `package:wayfinder/adoption.dart` (ADR-0020). `KnowledgeAdoption.plan`
  reads a project and resolves a Profile, writing nothing in the project. It
  lists every file it would write with its text or digest, every Git fetch,
  the Profile's source, release and chain, the skills it installs, the
  conflicts that stop it, and the gate the adopted bundle will have. A
  request without a ref pins the source's current default branch as its
  commit. A later plan refreshes the mirror and follows a default branch
  that has moved. The request's
  `allowFetch` decides each fetch, and an offline request reads the Profile
  cache as it is; either way a fetch that may not run throws
  `fetch-required`. Planning wraps an unreadable project as
  `adoption-failed`.
- `KnowledgeAdoption.apply` writes the seeded bundle (`index.md`, `log.md`
  and the seed concepts a host passes, with generated indexes),
  `wayfinder.json`, `wayfinder.lock` and the Profile skills through the
  resolver, a `<bundle>/.okf.lock` line in `.gitignore` unless it is listed
  there, and an optional host step, reporting each step. It refuses a plan
  with conflicts (`adoption-conflict`), one another Profile cache planned
  (`adoption-invalid`), or one whose inputs changed (`adoption-stale`,
  `resolution-stale`) before writing. It holds the project's `get` lock from
  that check on (`resolution-busy`), checks its cancellation before each
  step, and undoes the earlier steps when one fails, reporting a step whose
  undo failed as `undo-failed`. A marked skill directory it does not
  install is a conflict (`skill-foreign`), so adoption deletes nothing.
  Its closing validation binds the bundle with the plan's `projectRoot`, so
  no `wayfinder.json` above the project applies.
- Adoption never writes `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or hooks; the
  plan returns the `### Knowledge bundle` block as text. `KnowledgeSeeds`
  holds the generic seed that the adopt-knowledge-bundle skill's
  `SEEDING.md` shows.
<<<<<<< HEAD
=======
<!--
Release bookkeeping: the `pruneProjectLocks` and `tryExclusive` bullets below
(#110) amend the `WayfinderFileLock` bullet above; fold them into it if both
ship in one release.
-->
>>>>>>> 9173ce0 (docs(core): keep the Projects bullets in place and word locked-only plans)
- `WayfinderProfileResolver.pruneProjectLocks` deletes the `get` lock file of
  each project whose root no longer exists, such as a removed worktree, once
  no `get` used it for a period (30 days by default), and returns the deleted
  files. It reads a lock's note only while the lock is free and leaves a held
  one. `WayfinderKnowledgeStore.prune` calls it.
- `WayfinderFileLock.tryExclusive` tries a refused lock again for up to
  100 ms before it returns null, so an `isHeld` probe, which holds a shared
  lock for an instant, never reads as a holder. `tryExclusive` and
  `exclusive` return a lock only while the file's path still names the file
  they locked (the same device and inode on POSIX), and otherwise open the
  path again, so a cleanup that deletes a lock file while holding it never
  leaves two holders on different files.
- `runGit` takes `start`, a `GitProcessStarter` (`startGitProcess` by
  default), so a host whose process layer starts every process runs the
  hardened Git through it: the starter receives the hardened arguments and
  the whole environment, and `GitProcess.kill` stops the command's tree.
  `maxOutputBytes` (`wayfinderGitMaxOutputBytes`, 64 MiB) bounds stdout: a
  command that writes more is stopped with `git-output-too-large` instead of
  returning a cut blob. Stderr keeps its last 64 KiB. Once a command exits,
  its stdout is read to its end and its stderr until it closes or a second
  passes without any, so a helper that holds stderr open, such as an SSH
  connection master, no longer holds the command. Both must end within ten
  seconds of the exit, or the command's `timeout` when shorter: a stdout
  still open then fails with `git-output-incomplete`, never returning part
  of it, a stderr still being written is cut, and either way
  `GitProcess.kill` is asked to stop the helpers; `cancel` still stops the
  read. A stopped command that does
  not exit within five seconds still fails.
- The rules a host's own runner would copy are public: `gitSubcommand`,
  which also skips the values of `--git-dir`, `--work-tree`, `--namespace`,
  `--config-env`, `--attr-source` and `--super-prefix`; `gitMayReachRemote`
  over `wayfinderGitRemoteSubcommands`, which adds `archive`, `fetch-pack`,
  `send-pack`, `maintenance` and `lfs`; `wayfinderSshCommand`, the SSH
  command Git would choose (`GIT_SSH_COMMAND`, `core.sshCommand`, `GIT_SSH`,
  `ssh`) in batch mode; and `wayfinderConfiguredSshCommand`, the
  `core.sshCommand` lookup before a remote command.
- Reading a Profile package is bounded (ADR-0015, ADR-0018, guide §9).
  `ProfilePackage.parseWithin` parses on an isolate of its own and kills it
  once it runs past its timeout (`ProfilePackage.parseTimeout`, ten
  seconds), throwing a `ProfilePackageException` with `timedOut` that names
  the rule whose `tests` were running. The resolver reads every package
  this way, bounded by its `packageTimeout`, and reports one that runs past
  it as the new `wayfinder/profile-timeout` diagnostic
  (`DiagnosticCode.profileTimeout`), so a package whose tests run a pattern
  that backtracks without end fails `get` and selection instead of holding
  them. A parse that stops on another error, such as a stack overflow in a
  rule's tests, throws a `ProfilePackageException` naming it, reported as
  `profile-invalid`, rather than parsing again unbounded on the caller.
  Every read runs the tests; no verdict is cached. Bitwild parses in about
  five milliseconds, so no package reads differently and package format
  stays 2.
- `WayfinderProfileResolver.status` reports, offline and without Git, a
  `ProfileResolutionStatus` with one `ProfileBindingStatus` per binding: a
  stable `ProfileBindingState` (`resolved`, `lock-missing`, `lock-stale`,
  `cache-missing`, `package-invalid`, `package-unsupported`,
  `package-timeout` or `composition-failed`), the locked chain, the chain
  members missing from the cache, the diagnostic `select` reports and its
  `profile-skill-stale` notes. `select`'s diagnostics are unchanged.
- `plan(lockedOnly: true)` resolves exactly the commits `wayfinder.lock`
  pins: it fetches a source only when its mirror is missing or lacks the
  locked commit, never re-resolves a ref (the lock's commits stay as
  written), and keeps the lock's bytes. It throws
  `ProfileLockChangeRequiredException` (`lock-change-required`) before any
  Git command when the lock as written would change, and once read for a
  package that disagrees with the lock. `ProfileResolutionPlan.lockedOnly`
  reports it, and the plan's JSON adds `locked_only`.
- `WayfinderProfileSource.locationOf` is the location the resolver gives a
  source, as `ProfileFetch.location` reports it. A `ProfileFetchPolicy` is
  all per-source consent needs: every Git command a resolution runs that can
  reach the network follows the policy's yes for that location.
- A Profile skill marker that cannot be read counts as no marker: validation
  warns `profile-skill-stale` instead of failing selection as
  `profile-unresolved`, `status` reports the binding `resolved` with that
  warning rather than `cache-missing`, and `get` leaves such a directory
  alone as it does any unmarked one.
<!--
Release bookkeeping: the bullets below amend the `status` and
`plan(lockedOnly: true)` bullets above; fold them in if both ship in one
release.
-->
- `plan(skills: false)` leaves Profile skills alone, so a host can fill the
  Profile cache without touching `.claude/skills` or `.agents/skills`: the
  plan reads no skill file from a mirror and refuses no skill directory, and
  its apply writes and deletes none. `ProfileResolutionPlan.includesSkills`
  reports it, and `ProfileResolutionPlan.skillDirectories` lists every
  directory a locked package's skill installs into with its state, including
  the unmarked and outside ones a plan with skills refuses. The plan's JSON
  adds `includes_skills` and `skill_directories`.
- `ProfileSkills.inspect` reports, for one skill revision and without
  writing, each skill directory as a `ProfileSkillDirectory`: its root, path,
  the revision its marker records and a `ProfileSkillDirectoryState`
  (`current`, `missing`, `stale`, `unmarked` or `outside`). `stale` is
  derived from it and reports the same paths.
- `get` refuses a file or symbolic link where a Profile skill directory
  goes, as it refuses a directory without the Profile's marker, before
  writing anything; it used to write the lock and fail while moving the
  skill into place. `ProfileSkills.unowned` and `ProfileSkills.write` count
  such an entry as unowned. `ProfileSkills.write` refuses a skill root that
  resolves outside the project with the `ProfileSkillDirectoriesException`
  `get` throws, rather than a `FileSystemException`, so a root a link moves
  outside after `get`'s check fails the same way.
- `status` reports as data, per binding: `copies`, one `ProfileLocalCopy`
  per chain member saying whether its source's mirror and its package file
  are in the Profile cache, with the source's location, so a consent gate
  names only the sources a locked-only plan contacts; `skillDirectories`, the
  states of a resolved chain's skill directories behind the
  `profile-skill-stale` notes; and `lockChange`, a `ProfileLockChange` for a
  lock that is missing or stale. `ProfileResolutionStatus.lockChange` is what
  a locked-only plan would refuse before running Git, including a lock entry
  no chain reaches, all from one read of the lock. The JSON adds `copies`,
  `lock_change` and `skill_directories`.
- `ProfileLockChangeRequiredException` carries a `ProfileLockChange`
  (`change`): its `ProfileLockChangeKind` (`lock-missing`,
  `configuration-changed`, `chain-missing`, `source-changed`,
  `package-changed` or `packages-unreached`), the binding it concerns, the
  lock entries that would change and the reason its message ends with. The
  constructor takes the change; `state` and `profile` derive from it, and
  `profile` is null for a missing lock or a changed configuration, which
  concern every binding.
- The project library's messages name no command (ADR-0018), and the
  `wayfinder` command keeps printing what to run. A diagnostic's
  `EngineDiagnostic.remedy`, a `DiagnosticRemedy`, says when resolving the
  Profiles again fixes it (`resolve-profiles`, or
  `resolve-profiles-from-mirror` when the cached mirror needs no fetch), and
  `WayfinderProfileResolutionException.remedy` when selecting new revisions
  does (`upgrade-profiles`). Results, text and SARIF do not report the
  remedy; `ProfileValidationResult.withDiagnosticMessages` rewords a
  result's diagnostics for a host to render. `get`'s refusal of a skill
  directory is a `ProfileSkillDirectoriesException`, with the refused
  `directories` and their `outsideRoots`, and `resolution-busy` a
  `ProfileResolutionBusyException`, naming the busy `projectRoot` or
  `source`. These messages lose their closing advice to run a command:
  `profile-unresolved` and `profile-skill-stale` diagnostics,
  `resolution-stale`, a locked commit no refresh finds, and
  `ProfileSkills.escapingProblem`. A stale lock's reason reads `the
  configuration changed after the lock was written`, a busy project
  `Another Profile resolution is changing <root>`, and a lock change found
  once a package is read names that package. A diagnostic for a missing or
  stale lock carries its `ProfileLockChangeKind`
  (`EngineDiagnostic.lockChange`), which `package:wayfinder/wayfinder.dart`
  now declares and `package:wayfinder/project.dart` still exports, so a host
  words the cause itself, as the command keeps `the configuration changed
  after wayfinder get`. Adoption's `bundle-okf-invalid` and `skill-foreign`
  conflicts no longer name `okf validate` or `wayfinder get`.

# 0.2.0

- `wayfinder` depends on `ack`, which replaces the engine's own JSON Schema
  evaluator. Ack evaluates every rule schema. The engine still admits only its
  keyword subset, checks a schema's property names against its subject's
  facts, and words every message.
  `SchemaCheck.schema` is the parsed rule schema; `SchemaCheck.defs`,
  `slots` and `compile` are gone. A rule schema now follows 2020-12 where the
  old evaluator did not: an empty `enum` matches nothing instead of being
  refused; a `$ref` below a `$defs` entry, a `$id` or `$schema` below the
  root and a `$schema` that does not name 2020-12 are unsupported; a
  malformed annotation (a non-string `title`, `description` or `$comment`,
  non-list `examples`, a non-boolean `deprecated`), a duplicate `required`
  or `type` entry and an empty `type` list are refused; and Ack words these
  refusals and a nonproductive `$ref` cycle.
- Ack also checks `wayfinder.json` and each package against the published
  schemas, and the engine words the first failure as before, with three
  changes: a root `null` is reported as "must not be null"; with several
  violations, the first is the first in Ack's keyword order rather than
  document order; and a number too large for a double is reported as "must
  contain only finite numbers". `schemaFailureWhere` is gone; it was never
  meant to be public.
- A non-finite frontmatter number (YAML `.inf`, `.nan`) reads as the string
  fact `Infinity` or `NaN`, as other non-JSON scalars already do, so a rule
  schema only ever sees JSON.
- A package may name its agent skill directory in `skill`
  (`ProfilePackage.skill`), relative to the package. A Profile id has at most
  64 characters (`ProfileId.maxLength`, `maxLength` in both schemas), the
  Agent Skills name limit, because the id names the installed skill. The new
  `wayfinder/profile-skill-stale` warning reports a Profile skill whose
  installed copy is not the locked revision, carried by
  `SelectedProfile.notes`.
- A package names its own parent in `extends`: `{"path"}` is the package at
  that path in the same repository at the same commit, and
  `{"git", "ref", "path"}` resolves its own revision (`PackageParent`,
  `SameRevision`, `OtherRevision`). `wayfinder.json` loses `extends`, and
  `applies_to` needs at least one path. `ProfileValidator.validate` takes a
  `ProfileSelection`, either `SelectedProfile` or `UnselectedProfile`,
  instead of reading the configuration itself; `WayfinderProjectConfig.bind`
  finds a bundle's binding or throws `BundleBindingException` with its one
  diagnostic. `ProfileSourceResolution`, `WayfinderProjectConfig.read`,
  `resolve` and `WayfinderResolvedConfig` are gone. Whenever a Profile was
  selected, including under `BLOCKED BY OKF`, the JSON result names it as
  `profile.id` and `profile.release` and its chain as `profile.chain`
  (`{id, release, commit}`, root first). Only `NOT ASSESSED` omits them.
  Text prints `Profile <id> <release>: <state>`, and SARIF gains the
  `profile_id` run property.
- A Profile is one package file, `wayfinder-profile.json` in package
  format 2, read by `ProfilePackage.parse` for every Profile alike. The
  manifest and rule catalog are merged (`standard_types` is `types`,
  `frontmatter_keys` is a list of definitions, the rule shape moves in, the
  per-rule `ref` is gone), `wayfinder-rules.schema.json` folds into
  `wayfinder-profile.schema.json`, and the engine embeds no Profile. Bitwild
  is the package at `profiles/bitwild/` with id `bitwild-profile`, so its
  findings are `bitwild-profile/*` (formerly `concepta-profile/*`), and it is
  fetched like any Profile; no chain has to reach it. A package id is the
  finding namespace, in kebab-case. `EffectiveProfile.compose` merges a
  chain and the project additions, and a name collision, a repeated
  frontmatter key or a tag equal to another vocabulary value is the
  `wayfinder/profile-composition` diagnostic (a tag collision was
  `config-invalid`). A malformed package is `wayfinder/profile-invalid`; a
  package with another `format`, an OKF release this okf cannot read or an
  unknown builtin is `wayfinder/profile-unsupported`. Findings and summary
  entries carry `help_uri`, the package `docs` URI with the rule id as its
  fragment, instead of `rule`; SARIF rule descriptors carry `helpUri` and
  lose `properties.ref`. Builtins are engine capabilities with params:
  `files-present` (`paths`), `path-targets-exist` (`fields`) and
  `matches-generated` (`generator`, `version`, `keep`, `extra`), and
  the generator declares the package's `implements.release`. The JSON
  result gains `engine.okf` and SARIF `tool.extensions` names the okf
  package the engine generates with. New root facts `has_concepts` and
  `index_links`, and the Bitwild rule `root-index-lists-log`. The
  generator is `tool/generate_published_schemas.dart`, writing
  `published_schemas.g.dart`.
- The engine selects a Profile only through `wayfinder.json`.
  The 2026.2 dispatch through an in-bundle `profile.md` declaration is gone,
  with its `types.md` and `actors.md` registry readers and its index
  projection. A bundle with no `wayfinder.json` above it is `NOT ASSESSED`
  with `wayfinder/config-missing` and gate `INCOMPLETE`, whatever its root
  files say, and `--fix` writes nothing there. A `profile.md` no longer
  exempts a bundle from `wayfinder/config-invalid` or
  `wayfinder/bundle-unbound`. The 19 builtins frozen for 2026.2, the
  builtins' `installedOnlyIn` restriction, `tag-literal-duplication` (dead
  since 2026.3 checks tag collisions while reading the binding), and the
  2026.2-only `reserved` param of `root-structure-files` are deleted, as are
  `LegacyRegistries`, `EffectiveProfile.legacyDispatch`,
  `Vocabulary.standardTypes`, `legacyProfileRelease`, and
  `legacyStandardTypes`, and the `yaml` dependency is dropped. A 2026.2
  bundle keeps validating on wayfinder 0.1.x, or migrates to a
  `wayfinder.json` binding.
- The engine reports on its own run as `EngineDiagnostic`s, a closed set of
  `wayfinder/*` codes with a level, instead of dressing them as Profile
  findings. Release dispatch problems (`DispatchRule` is gone), the
  `link-graph-unavailable` and `configured-type-extension` catalog rules and
  their builtins, and `--fix` failure or refusal (`ProfileFix` is gone)
  become diagnostics. `ProfileValidationResult` holds a sealed
  `ProfileAssessment` (`Assessed`, `BlockedByOkf`, `NotAssessed`) and derives
  `gate`: `FAIL` when OKF fails or a finding is an error, else `INCOMPLETE`
  when a diagnostic is an error, else `PASS`, exiting 0, 1 or 2. JSON gains
  `diagnostics` and `gate` and loses `judgment_rules` and `automated_gate`;
  `fix` is `{written}`. Profile state `UNSUPPORTED` becomes `NOT ASSESSED`.
  SARIF reports diagnostics as invocation notifications with
  `driver.notifications` descriptors, and `executionSuccessful` is false only
  for an error diagnostic. `internalErrorJson` and `internalErrorSarif`
  describe a run that stopped. A link graph that cannot be built now makes
  the gate `INCOMPLETE` rather than `FAIL`, and skips every rule that reads
  a link fact: by name, through a `$ref` applied to the subject, or through a
  keyword that reads the whole key set (`propertyNames`,
  `additionalProperties`, `minProperties`, `enum`, `const`).
  `ProfileValidator` takes a `buildGraph` function so a test can force that
  path.
- `index-current` and `validate --fix` compare an index with CRLF line
  endings, as a Windows checkout writes it, equal to the generated LF text,
  so neither reports nor rewrites it.
- `validate --fix` replaces each generated index atomically, refuses a
  symbolic link at any path segment, and reports a failed write with the
  files already written. SARIF locations inside the working directory
  are relative to a recorded `WORKINGDIR` base, and summary results carry
  level `none`. A failed fix fails the SARIF invocation through its
  `wayfinder/fix-failed` notification, and the run's `fix` property lists
  the files written before it.
- `ProfileFinding` takes a `FindingDescriptor`,
  which only an error or advisory descriptor can become, so a note rule has
  no path to a finding.
- A rule schema names a composed vocabulary as `{"$ref": "#/$defs/<slot>"}`,
  such as `#/$defs/profile.types`. The engine supplies those entries, so a
  package or rule `$defs` entry may not use a slot id. The `x-slot` keyword
  is gone, and any `x-` keyword now makes a package unsupported rather than
  being ignored, so every rule schema is plain JSON Schema.
- `ProfilePackage.parse` rejects more at load: a rule whose own examples
  disagree with its schema; `each` over a fact that is not a list;
  `failing_field` that is not an element field; a `properties` or
  `required` name at the subject level, inline or through a `$ref` applied
  to the same instance, that no fact or element field of a closed subject
  carries; params for a builtin that declares none; and a
  message placeholder the builtin does not fill. `failingExamples` is gone;
  load runs the examples.
- Bitwild 2026.3 `relationship-shape` fails a `relationships` value that is
  null, and an entry whose `resource` okf resolves as `invalid` or as a
  scope `descriptor`. The rule moves to
  the `concept` subject: each `relationships` element carries the authored
  `entry` with the `resolution` beside it, and a non-list value stays the
  value itself. `okfFieldEdges` resolves targets as source resources, so
  prose resolves as `descriptor` rather than `unresolved`. The engine tests
  a non-list `each` fact as one `{"value": ...}` instance instead of failing
  it outright, so the rule's schema decides.
- Bitwild 2026.3 reports an undeclared relationship name as the new
  `used-relationship-declared` (vocabulary, error), like
  `used-type-registered` and `used-actor-registered`, instead of
  `relationship-shape`, which now checks that `relationship` is a nonempty
  string, not that it is declared. The new rule tests a name only once the entry is a
  mapping with nonempty text there, so one defect never reports under both.
- `{failing}` and `{fact}` placeholders render a non-string value as compact
  JSON instead of Dart's `{key: value}` text, so a failing relationships
  entry reads as it was authored. Strings are unchanged.
- A failure while resolving relationship targets no longer drops the
  `relationships` and `inbound` facts silently. okf's graph and the
  relationship edges resolve as one link layer; when it fails, no link fact
  exists for a link rule to pass on, and the run reports it.
  `BundleFacts.project` takes a `buildGraph` function so a test can force
  that path.
- Export `OkfLinkField`, `OkfFieldEdge` and `okfFieldEdges`, the typed
  link-field model and resolution `wayfinder_embeddings` and the CLI graph
  shared with the engine, plus `relationshipsLinkField` for the Profile's
  `relationships` key. The engine's relationship facts resolve through the
  same function.
- Bitwild 2026.3 reports what it permits as summary entries instead of
  advisories. Rules take a third severity, `note`, whose results
  fill `ProfileValidationResult.summary` (`ProfileSummaryEntry`), JSON
  `profile.summary`, a text `Summary:` block and SARIF results of kind
  `informational` with level `none`, and never affect a state or the exit code.
  `internal-link-unresolved` and `relationship-unresolved` become notes. `evaluate` returns findings and
  summary entries apart. A declared tag that equals a type, status, trust
  tier or relationship name fails `WayfinderProjectConfig.parse` and binding
  composition, and Bitwild 2026.3 drops `tag-literal-duplication`.
- Bitwild 2026.3 types relationships in the `relationships` frontmatter key
  instead of a `# Relationships` body section. Bitwild 2026.3 declares
  the key in its new `frontmatter_keys`, renames `frontmatter-fields-okf` to
  `frontmatter-fields-declared`, adds `relationship-shape` (error) and the
  `relationship-bundle-relative` and `relationship-unresolved` advisories, and
  drops `relationships-shape` and `relationship-label-extension`.
  `tag-literal-duplication` compares tags with the declared relationship
  names. Relationship names are vocabulary: Bitwild declares eleven and
  `WayfinderProfileBinding.relationships` adds project names. A package
  declaring an OKF key fails to load.
- Bitwild 2026.3 indexes are okf's generated output: `index-current` replaces
  `index-semantic-projection` and `directory-index-present` in Bitwild 2026.3
  and reports each generated index that is missing or differs.
  `ProfileValidator.validate(fix: true)` writes those indexes first and
  reports what it wrote as `ProfileValidationResult.fixed`. It also reports a
  leftover `index.md` the generator no longer writes, such as one in a
  `raw/` tier, so the parent index stops linking to it. Conformance now
  depends on okf's generator output; the configured-fixture goldens fail if an
  okf release changes it, which is the signal to update the guide's pin.
- Add direct-source project bindings in `wayfinder.json`, with strict type,
  tag, actor, and path checks. Version 1 accepts only `source` +
  `applies_to`; the earlier unpublished `bundles` / `implements` draft is not
  a compatibility form. Bitwild's twelve types include OKF's Attested
  Computation.
- Inspect OKF independently before Profile selection. Bitwild's
  `okf-release-binding` checks the root `okf_version`.
- Report a configured project type at the configuration path as supplied, or
  `wayfinder.json` when discovered, instead of the file's absolute path.
- Stop reporting nested `profile.md`, `types.md`, or `actors.md` concepts.
  Bitwild forbids only the legacy root registries.
- Bitwild 2026.3 `log-entry-lead-word` no longer fails a root log without
  entries. The rule requires a lead word on every entry, not that entries
  exist. okf's `missing-log-date` and `empty-log-date` errors still reject
  such a log before Profile validation runs.

# 0.1.0

- Validate against Concepta Profile 2026.2, which adopts the OKF 0.2 revision
  where every timestamp is an ISO 8601 datetime with an explicit UTC offset, and
  pins the specification to its canonical `open-knowledge-format` repository at
  `ad30107`. A bundle still declaring `concepta_profile: "2026.1"` now reports an
  unsupported release rather than a conformance verdict; update the declaration
  and, where timestamps are date-only, run `okf format --migrate-timestamps`.
- Depend on `okf` ^0.5.0. A date-only timestamp is reported through okf's
  non-blocking `okf/timestamp-without-offset` advisory, so a bundle conformant
  under 2026.1 stays conformant once its declaration is updated.
- Raise the Dart floor from 3.6.0 to 3.11.0, matching every Concepta
  package. A consumer on an older SDK no longer resolves this package and
  must upgrade Dart to take 0.1.0.

# 0.0.1

Core library replaces okf_profile; import package:wayfinder/wayfinder.dart. Validation contracts remain unchanged. The command and MCP server now live in wayfinder_cli.

# Changelog

## 0.2.1-dev.0

- Expose the existing validator and result contracts for Wayfinder without changing
  `okfp` commands, validation semantics or exit codes.

Release history of the `okf_profile` Dart package (the `okfp` toolchain).
This is package semver; profile releases are recorded in `profile/`, not here.

## 0.2.0

- Migrate to okf 0.2.0 and adopt its finding contract as the wire format
  (ADR-0008): the `okf.report` JSON object is now okf's own projection — a
  canonically ordered `findings` array of `{id, severity, message, location}`
  objects with namespaced kebab-case IDs — and the separate `okf.load_issues`
  channel is retired, because load failures are error-severity findings in the
  same report.
- Text output reports the OKF component as `N error(s), N advisory(ies)`;
  the `warning` tier no longer exists upstream.
- `ProfileValidator` validates through okf's single report-composition seam
  (`OkfBundleLoadResult.validate()`) and no longer takes an okf validator.
- Profile findings speak the same finding grammar (ADR-0008): each JSON
  finding is the okf projection — `{id, severity, message, location}` — plus
  the `profile_release` and `rule` references guide §4.2 requires, and
  findings sort in okf's canonical report order (path, line, column, id,
  severity, message) instead of emission order.
- Add the profile rule descriptor registry (id, severity, normative rule
  reference), mirroring okf's `okfSpecRuleDescriptors`. Every finding is
  built from its rule's descriptor, so id, severity, and rule reference
  cannot drift from the registry — a call site names only the rule, the
  observation, and its path — and a corpus test holds every emitted finding
  to a registered rule.
- The automated gate's exit codes are okf's `OkfExitCode` contract:
  `success`/`findings`/`usage` for PASS/FAIL/UNSUPPORTED (values unchanged).
- Index and log parsing go through okf's `OkfIndexDocument`/`OkfLogDocument`
  entry format instead of a hand-rolled markdown-AST parallel; ADR-0007's
  percent-decoded target comparison is unchanged on top of it. okf 0.2.0's
  angle-bracket destination form means a raw `)` no longer forces the
  percent-encoded spelling; the authoring skill teaches both. The §9 expected
  projection stays profile-owned — okf's generic index generator synthesizes
  directory descriptions the Concepta projection deliberately leaves empty.

## 0.1.1

- Enforce the Profile 2026.1 `raw/` tier amendment (ADR-0006): non-index
  markdown under a `raw/` directory in `references/` fails deterministically
  as `concepta-profile/raw-directory-markdown`, and a `raw/` directory sitting
  directly under `references/` fails as
  `concepta-profile/raw-directory-placement` — the tier is per source
  directory, and `references/` itself is not one.

## 0.1.0

- Bootstrap the `okf_profile` package and the `okfp` command-line interface,
  as a pub workspace member at `packages/wayfinder/`.
- Ship the closed `validate <bundle> [--output text|json]` automated gate for
  the Concepta Profile, backed by the independent OKF 0.2 result.
- Keep deterministic Profile findings, contextual judgment, and automated-gate
  states separate in stable text and JSON contracts.
