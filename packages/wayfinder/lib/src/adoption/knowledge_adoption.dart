import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../diagnostics.dart';
import '../knowledge_assessment.dart';
import '../profile_package.dart';
import '../project/cancellation.dart';
import '../project/exception.dart';
import '../project/profile_resolver.dart';
import '../project/profile_skills.dart';
import '../validation.dart';
import '../wayfinder_config.dart';
import 'inputs.dart';
import 'model.dart';
import 'request.dart';
import 'seeds.dart';

/// What [KnowledgeAdoption.apply] would write, from
/// [KnowledgeAdoption.plan]. Planning wrote nothing in the project; it may
/// have fetched the Profile source into the Profile cache, as [fetches]
/// lists.
final class KnowledgeAdoptionPlan {
  KnowledgeAdoptionPlan._({
    required this.request,
    required this.projectRoot,
    required this.bundle,
    required this.mode,
    required this.profile,
    required this.fetches,
    required this.files,
    required this.skills,
    required this.conflicts,
    required this.agentInstructions,
    required this.validation,
    required String dataDirectory,
    required AdoptionInputs inputs,
    required CandidateResolution resolution,
    required List<int> configuration,
    required Map<String, List<int>> bundleFiles,
    required List<int>? gitignoreAppend,
    required List<String> hostInputs,
  }) : _dataDirectory = dataDirectory,
       _inputs = inputs,
       _resolution = resolution,
       _configuration = configuration,
       _bundleFiles = bundleFiles,
       _gitignoreAppend = gitignoreAppend,
       _hostInputs = hostInputs;

  final AdoptionRequest request;

  /// The absolute project directory.
  final String projectRoot;

  /// The bundle directory, relative to [projectRoot], as a POSIX path.
  final String bundle;

  /// Whether applying seeds a new bundle or binds the existing one.
  final AdoptionBundleMode mode;

  /// The Profile `wayfinder.json` binds, and the chain the lock pins.
  final AdoptionProfile profile;

  /// Every Git fetch adoption made, in order: planning made them, into the
  /// Profile cache only, each as [AdoptionRequest.allowFetch] allowed;
  /// applying fetches nothing.
  final List<ProfileFetch> fetches;

  /// Every file applying writes, in the order it writes them. Never
  /// `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or a hook.
  final List<AdoptionFile> files;

  /// Each Profile skill the chain ships, by id, with the project directories
  /// that hold it (`.claude/skills/<id>` and `.agents/skills/<id>`);
  /// `written` is false for one already installed at the locked commit.
  final List<MaterializedSkill> skills;

  /// What stops applying. [KnowledgeAdoption.apply] refuses a plan with any,
  /// before writing anything.
  final List<AdoptionConflict> conflicts;

  /// The `### Knowledge bundle` block for the project's `AGENTS.md`, with
  /// the request's instruction lines. Adoption never writes it.
  final String agentInstructions;

  /// The bundle validated as applying leaves it, from the files above and
  /// the planned Profile. `PASS` is what completes adoption.
  final ProfileValidationResult validation;

  /// The Profile cache the plan resolved into, which applying reads.
  final String _dataDirectory;
  final AdoptionInputs _inputs;
  final CandidateResolution _resolution;
  final List<int> _configuration;
  final Map<String, List<int>> _bundleFiles;
  final List<int>? _gitignoreAppend;

  /// The request's host inputs, normalized, which applying checks with the
  /// rest of [_inputs].
  final List<String> _hostInputs;

  /// Whether [KnowledgeAdoption.apply] can write this plan: it has no
  /// conflicts.
  bool get applicable => conflicts.isEmpty;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'bundle': bundle,
    'mode': mode.wireValue,
    'profile': profile.toJson(),
    'fetches': [for (final fetch in fetches) fetch.toJson()],
    'files': [for (final file in files) file.toJson()],
    'skills': [for (final skill in skills) skill.toJson()],
    'conflicts': [for (final conflict in conflicts) conflict.toJson()],
    'applicable': applicable,
    'gate': validation.gate.wireValue,
    'agent_instructions': agentInstructions,
  };
}

/// What [KnowledgeAdoption.apply] did.
final class KnowledgeAdoptionResult {
  const KnowledgeAdoptionResult({
    required this.projectRoot,
    required this.bundle,
    required this.steps,
    required this.written,
    required this.validation,
    required this.agentInstructions,
  });

  final String projectRoot;
  final String bundle;

  /// Each step's report, in the order the steps ran.
  final List<AdoptionStepReport> steps;

  /// The project-relative files written, as the plan listed them.
  final List<String> written;

  /// The adopted bundle's validation; null when validating failed to run,
  /// which the `validate` step reports.
  final ProfileValidationResult? validation;

  /// The `### Knowledge bundle` block the project's `AGENTS.md` still needs.
  final String agentInstructions;

  /// Adoption is complete when the adopted bundle's gate is `PASS`
  /// (guide §2.3).
  bool get complete => validation?.gate == GateState.pass;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'bundle': bundle,
    'steps': [for (final step in steps) step.toJson()],
    'written': written,
    'gate': validation?.gate.wireValue,
    'complete': complete,
    'agent_instructions': agentInstructions,
  };
}

/// Adopts a Profile in a project: binds it in `wayfinder.json`, locks and
/// installs it through [resolver], seeds the bundle, and adds the
/// `.okf.lock` line to `.gitignore`. [plan] writes nothing in the project;
/// [apply] writes exactly what the plan lists, or nothing.
///
/// It never writes `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or Git hooks: the
/// plan returns the agent-instruction block as text, and registering an MCP
/// server or hooks is the host's choice. Run it on the isolate that does the
/// process's okf bundle I/O (ADR-0018); only the Profile assessment may run
/// elsewhere, through a [KnowledgeAssessor].
final class KnowledgeAdoption {
  /// [resolver] resolves, locks and installs the Profile; [assess] judges
  /// the bundle against it, by default on the calling isolate; [clock]
  /// dates the first log entry.
  KnowledgeAdoption({
    required this.resolver,
    KnowledgeAssessor assess = assessOnCallingIsolate,
    DateTime Function() clock = DateTime.now,
  }) : _assess = assess,
       _clock = clock;

  /// Resolves the Profile and writes the lock and skills. Applying holds
  /// its `get` lock of the project, so no `get` changes the project
  /// meanwhile.
  final WayfinderProfileResolver resolver;
  final KnowledgeAssessor _assess;
  final DateTime Function() _clock;

  /// Reads the project, resolves the requested Profile, and returns what
  /// [apply] would write. Writes nothing in the project. Resolving may
  /// clone or refresh Profile sources in the Profile cache, each as
  /// [AdoptionRequest.allowFetch] allows; an offline request reads the
  /// cache as it is. A fetch it may not make throws
  /// `ProfileFetchRequiredException` (`fetch-required`) naming it.
  ///
  /// The Profile is the one the package at the request's source declares;
  /// a request that names another throws [AdoptionProfileConflictException]
  /// (`adoption-profile-conflict`). The bundle as applying leaves it is
  /// judged once, through the adoption's [KnowledgeAssessor], which gets
  /// [cancel] and whose failures, such as `assessment-timeout`, planning
  /// throws.
  ///
  /// Throws `adoption-invalid` for a request that cannot describe an
  /// adoption, such as a malformed bundle path, source, seed concept or
  /// host input; `adoption-failed` when the project or Git cannot be read;
  /// and the resolver's codes, such as `profile-unresolved`, when the
  /// Profile does not resolve. What the project holds is reported as
  /// [KnowledgeAdoptionPlan.conflicts].
  Future<KnowledgeAdoptionPlan> plan(
    AdoptionRequest request, {
    WayfinderCancellation? cancel,
  }) async {
    try {
      return await _plan(request, cancel);
    } on FileSystemException catch (error) {
      throw WayfinderException(
        'adoption-failed',
        'Adoption could not be planned: ${error.message}'
            '${error.path == null ? '' : ' (${error.path})'}.',
      );
    } on ProcessException catch (error) {
      throw WayfinderException(
        'adoption-failed',
        'Adoption could not be planned: ${error.executable} could not run: '
            '${error.message}.',
      );
    }
  }

  Future<KnowledgeAdoptionPlan> _plan(
    AdoptionRequest request,
    WayfinderCancellation? cancel,
  ) async {
    throwIfCancelled(cancel);
    final projectRoot = p.normalize(
      Directory(request.projectRoot).absolute.path,
    );
    if (await FileSystemEntity.type(projectRoot) !=
        FileSystemEntityType.directory) {
      throw _invalid('Project $projectRoot is not a directory.');
    }
    final bundle = _bundlePath(request.bundle);
    final concepts = _concepts(request.concepts);
    final hostInputs = _hostInputs(request.hostInputs);
    if (request.bindExisting && concepts.isNotEmpty) {
      throw _invalid(
        'Seed concepts need a new bundle; binding an existing one writes '
        'nothing in it.',
      );
    }
    final git = request.source.git;
    if (WayfinderProfileSource.locationProblem(git) case final problem?) {
      throw _invalid('Profile source $git $problem.');
    }
    final path = p.posix.normalize(request.source.path);
    // Refuse a request that cannot be a binding before any Git runs.
    _configuration(
      request,
      bundle,
      id: request.profile ?? _anyProfile,
      ref: request.source.ref ?? _anyCommit,
      path: path,
    );

    final inputs = await AdoptionInputs.read(
      projectRoot,
      bundle,
      hostInputs: hostInputs,
    );
    for (final path in hostInputs) {
      switch (inputs.entries[path]) {
        case AdoptionInputs.outside:
          throw _invalid(
            'Host input $path resolves through a symbolic link outside the '
            'project, to the project directory itself, or into .git. Name '
            'a path inside the project.',
          );
        case AdoptionInputs.unresolved:
          throw _invalid(
            'Host input $path passes through more symbolic links than '
            'resolve, as a loop of links does.',
          );
      }
    }
    final conflicts = <AdoptionConflict>[
      for (final path in const ['wayfinder.json', 'wayfinder.lock'])
        if (inputs.entries[path] != 'absent')
          AdoptionConflict(
            path == 'wayfinder.json' ? 'configuration-exists' : 'lock-exists',
            path,
            '$path already exists. Adoption starts a project binding; '
            'changing an existing one is migration work.',
          ),
    ];
    final mode = await _bundleMode(projectRoot, bundle, request, conflicts);

    // The package's own id keys the binding; a request without a ref binds
    // the commit its default branch resolves to.
    final (:package, fetches: sourceFetches) = await resolveSourcePackage(
      resolver,
      projectRoot: projectRoot,
      git: git,
      ref: request.source.ref,
      path: path,
      offline: request.offline,
      allowFetch: request.allowFetch,
      cancel: cancel,
    );
    if (request.profile case final requested? when requested != package.id) {
      throw AdoptionProfileConflictException(
        requested: requested,
        declared: package.id,
        git: git,
        path: path,
        commit: package.commit,
      );
    }
    final id = package.id;
    final source = WayfinderProfileSource(
      git: git,
      ref: package.ref,
      path: path,
    );
    final configuration = _configuration(
      request,
      bundle,
      id: id,
      ref: source.ref,
      path: path,
    );
    final configurationBytes = utf8.encode(configuration);
    final resolution = await planCandidateResolution(
      resolver,
      projectRoot: projectRoot,
      configuration: configurationBytes,
      offline: request.offline,
      allowFetch: request.allowFetch,
      pinned: package,
      cancel: cancel,
    );
    final fetches = [...sourceFetches, ...resolution.plan.fetches];
    final problems = resolution.skillProblems;
    for (final root in ProfileSkills.roots) {
      if (problems.any(
        (directory) =>
            directory.root == root &&
            directory.state == ProfileSkillDirectoryState.outside,
      )) {
        conflicts.add(
          AdoptionConflict(
            'skill-root-escapes',
            root,
            '$root resolves outside the project through a symbolic link, so '
                'adoption would not install the Profile skill there. Point it '
                'inside the project and plan again.',
          ),
        );
      }
    }
    for (final directory in problems) {
      if (directory.state != ProfileSkillDirectoryState.unmarked) continue;
      conflicts.add(
        AdoptionConflict(
          'skill-unowned',
          directory.path,
          '${directory.path} already exists without a ${ProfileSkills.marker} '
              'marker, so adoption would not install the Profile skill there. '
              'Move it aside and plan again.',
        ),
      );
    }
    for (final directory in resolution.plan.removedSkills) {
      conflicts.add(
        AdoptionConflict(
          'skill-foreign',
          directory,
          '$directory holds a Profile skill Wayfinder installed that this '
              'adoption does not install, so resolving the project\'s '
              'Profiles again would delete it. Move it aside or remove it, '
              'and plan again.',
        ),
      );
    }

    final composed = resolution.profiles[id]!;
    final chain = ProfileLock(
      configurationSha256: '',
      packages: resolution.plan.packages,
    ).chainOf(id)!;
    final profile = AdoptionProfile(
      id: id,
      release: chain.last.release,
      git: source.git,
      ref: source.ref,
      path: source.path,
      commit: chain.last.commit,
      chain: List.unmodifiable(chain),
    );
    final selection = SelectedProfile(
      composed,
      config: ProjectFileLocation(
        path: 'wayfinder.json',
        file: p.join(projectRoot, 'wayfinder.json'),
      ),
      projectRoot: projectRoot,
      commits: {for (final package in chain) package.id: package.commit},
    );

    final bundleRoot = p.joinAll([projectRoot, ...p.posix.split(bundle)]);
    final bundleFiles = SplayTreeMap<String, List<int>>();
    final OkfBundleLoadResult loaded;
    if (mode == AdoptionBundleMode.seed) {
      final seeded = _seed(
        bundleRoot,
        selection,
        concepts,
        log: KnowledgeSeeds.log(
          date: KnowledgeSeeds.isoDate(request.date ?? _clock()),
          action: request.logAction,
          description: request.logDescription,
        ),
      );
      loaded = seeded.loaded;
      for (final MapEntry(:key, :value) in seeded.files.entries) {
        bundleFiles[key] = utf8.encode(value);
      }
    } else {
      loaded = await const OkfBundleLoader().inspect(bundleRoot);
      if (!loaded.validate().isConformant) {
        conflicts.add(
          AdoptionConflict(
            'bundle-okf-invalid',
            bundle,
            '$bundle fails OKF, so adoption does not bind it. Repair what '
                'OKF validation reports and plan again.',
          ),
        );
      }
    }
    final validation = (await _assess(
      KnowledgeAssessmentInput.bundle(bundle: loaded, selection: selection),
      cancel,
    )).candidate;
    throwIfCancelled(cancel);

    final (gitignore, gitignoreAppend) = await _gitignore(
      projectRoot,
      bundle,
      request,
      conflicts,
    );
    final files = <AdoptionFile>[
      for (final MapEntry(:key, :value) in bundleFiles.entries)
        _file(
          '$bundle/$key',
          AdoptionFileKind.bundle,
          AdoptionFileAction.create,
          value,
          content: utf8.decode(value),
        ),
      _file(
        'wayfinder.json',
        AdoptionFileKind.configuration,
        AdoptionFileAction.create,
        configurationBytes,
        content: configuration,
      ),
      _file(
        'wayfinder.lock',
        AdoptionFileKind.lock,
        AdoptionFileAction.create,
        utf8.encode(resolution.lockText),
        content: resolution.lockText,
      ),
      for (final id
          in resolution.skillFiles.keys.toList()
            ..sort((left, right) => left.value.compareTo(right.value)))
        ...await _skillFiles(
          projectRoot,
          resolution.plan.packages[id]!,
          resolution.skillFiles[id]!,
        ),
      ?gitignore,
    ];
    assert(files.every((file) => !_neverWritten.contains(file.path)));
    return KnowledgeAdoptionPlan._(
      request: request,
      projectRoot: projectRoot,
      bundle: bundle,
      mode: mode,
      profile: profile,
      fetches: List.unmodifiable(fetches),
      files: List.unmodifiable(files),
      skills: resolution.plan.skills,
      conflicts: List.unmodifiable(conflicts),
      agentInstructions: KnowledgeSeeds.knowledgeBundleInstructions(
        bundle: bundle,
        lines: request.instructionLines,
      ),
      validation: validation,
      dataDirectory: _dataDirectoryOf(resolver),
      inputs: inputs,
      resolution: resolution,
      configuration: configurationBytes,
      bundleFiles: Map.unmodifiable(bundleFiles),
      gitignoreAppend: gitignoreAppend,
      hostInputs: hostInputs,
    );
  }

  /// Writes [plan], one [AdoptionStep] at a time, then validates the
  /// bundle.
  ///
  /// The check step refuses a plan with conflicts (`adoption-conflict`), one
  /// another adoption's Profile cache planned (`adoption-invalid`), and one
  /// whose project files, bundle, skill directories, host inputs or Profile
  /// cache changed since planning (`adoption-stale`, naming the changed
  /// paths in [KnowledgeAdoptionException.changedPaths], and
  /// `resolution-stale`), before writing anything. It takes the resolver's
  /// `get` lock of the project and holds it until every step has finished
  /// or been undone, so no `get` or other adoption changes the project
  /// meanwhile; while another holder has it, the check fails with
  /// `resolution-busy`. [cancel] is checked as each step starts
  /// (`cancelled`).
  ///
  /// [hostStep] runs the host's own writes, such as placing
  /// [KnowledgeAdoptionPlan.agentInstructions] in `AGENTS.md`, as the
  /// [AdoptionStep.host] step after Wayfinder's files are in place. When it
  /// throws, every earlier step is undone like any other failure; adoption
  /// cannot undo the host's writes, so it undoes its own partial writes
  /// before throwing. Once it returns, its writes stay, whatever follows. A
  /// file it writes belongs in the request's `hostInputs`, so the check step
  /// refuses the plan when that file changed since planning.
  ///
  /// [onStep] hears each step as it happens, on the calling isolate: an
  /// [AdoptionStepOutcome.started] report as a step begins, then its end
  /// (`done`, `skipped` or `failed`), and, after a failure, an `undone` or
  /// `undo-failed` report for each earlier step as its undo finishes, latest
  /// first. A host shows progress with it. When it throws for a step's
  /// `started`, `done` or `skipped` report, that step fails with what it
  /// threw, its own writes and the earlier steps are undone, and apply
  /// throws as for any failure, so a test can stop adoption at any step.
  /// What it throws for a report of a failure or an undo is ignored, since
  /// apply already reports that failure, and so is what it throws for the
  /// host step's `done`, since the host's writes are then in place and
  /// adoption cannot undo them.
  ///
  /// When a step fails, the steps before it are undone in reverse order and
  /// [KnowledgeAdoptionException] reports each step, so the project holds no
  /// partial bundle unless a step reports `undo-failed`. Validation runs
  /// last, after the lock is released, and undoes nothing: a gate other
  /// than `PASS` returns a result that is not
  /// [KnowledgeAdoptionResult.complete]. It binds the bundle within the
  /// plan's project root, so it never reads a `wayfinder.json` above it, and
  /// judges it through the adoption's [KnowledgeAssessor] with [cancel]. A
  /// validation that fails to run, cancelled or stopped by the assessor
  /// included, reports the validate step `failed` with its code and leaves
  /// [KnowledgeAdoptionResult.validation] null.
  Future<KnowledgeAdoptionResult> apply(
    KnowledgeAdoptionPlan plan, {
    WayfinderCancellation? cancel,
    Future<void> Function()? hostStep,
    void Function(AdoptionStepReport report)? onStep,
  }) async {
    final run = _Run(onStep);
    final root = plan.projectRoot;
    try {
      run.start(AdoptionStep.check, cancel);
      if (plan.conflicts case [final first, ...final rest]) {
        throw WayfinderException(
          'adoption-conflict',
          '${first.message}'
              '${rest.isEmpty ? '' : ' The plan has ${rest.length} more '
                        'conflict${rest.length == 1 ? '' : 's'}.'}',
        );
      }
      if (plan._dataDirectory != _dataDirectoryOf(resolver)) {
        throw _invalid(
          'The plan resolved the Profile into ${plan._dataDirectory}, and '
          "this adoption's resolver uses ${_dataDirectoryOf(resolver)}. Plan "
          'again with this adoption.',
        );
      }
      await withProjectLock(
        resolver,
        root,
        () => _write(plan, run, cancel, hostStep),
      );
    } on Object catch (error) {
      // _write records its failure and undoes its steps while it still holds
      // the project; these finish a failure before or after it.
      run.fail(error);
      await run.undo();
      throw run.failure(error);
    }

    ProfileValidationResult? validation;
    try {
      run.start(AdoptionStep.validate, cancel);
      validation = await _validate(plan, cancel);
      run.done(const [], 'Gate ${validation.gate.wireValue}.');
    } on Object catch (error) {
      validation = null;
      run.fail(error);
    }
    return KnowledgeAdoptionResult(
      projectRoot: root,
      bundle: plan.bundle,
      steps: List.unmodifiable([
        for (final record in run.records) record.report,
      ]),
      written: List.unmodifiable([for (final file in plan.files) file.path]),
      validation: validation,
      agentInstructions: plan.agentInstructions,
    );
  }

  /// The adopted bundle as `validate` reports it, binding it within the
  /// project root, with the Profile judged through the adoption's assessor.
  Future<ProfileValidationResult> _validate(
    KnowledgeAdoptionPlan plan,
    WayfinderCancellation? cancel,
  ) async {
    final bundle = _native(plan.projectRoot, plan.bundle);
    final selection = await selectWithProfileSources(
      bundle,
      projectRoot: plan.projectRoot,
      resolver: resolver,
    );
    throwIfCancelled(cancel);
    final loaded = await const OkfBundleLoader().inspect(bundle);
    throwIfCancelled(cancel);
    return (await _assess(
      KnowledgeAssessmentInput.bundle(bundle: loaded, selection: selection),
      cancel,
    )).candidate;
  }

  /// The steps from the check on, under the project's `get` lock. Undoes
  /// what they wrote before rethrowing a failure, so no `get` can start in
  /// between.
  Future<void> _write(
    KnowledgeAdoptionPlan plan,
    _Run run,
    WayfinderCancellation? cancel,
    Future<void> Function()? hostStep,
  ) async {
    final root = plan.projectRoot;
    final backups = <Directory>[];
    try {
      final changed = (await AdoptionInputs.read(
        root,
        plan.bundle,
        hostInputs: plan._hostInputs,
      )).changedSince(plan._inputs);
      if (changed.isNotEmpty) throw _StaleInputs(changed);
      await plan._resolution.checkCache();
      run.done();

      run.start(AdoptionStep.bundle, cancel);
      if (plan.mode == AdoptionBundleMode.seed) {
        await _writeBundle(plan, run.onUndo);
        run.done([
          for (final path in plan._bundleFiles.keys) '${plan.bundle}/$path',
        ]);
      } else {
        run.skipped('Bound the existing bundle without writing in it.');
      }

      run.start(AdoptionStep.configuration, cancel);
      final configuration = File(p.join(root, 'wayfinder.json'));
      await _writeAtomically(configuration, plan._configuration);
      run.onUndo(() => _deleteIfHolds(configuration, plan._configuration));
      run.done(const ['wayfinder.json']);

      run.start(AdoptionStep.profile, cancel);
      await _installProfile(plan, run, backups);

      run.start(AdoptionStep.gitignore, cancel);
      if (plan._gitignoreAppend case final append?) {
        final gitignore = File(p.join(root, '.gitignore'));
        final original = await _readBytes(gitignore);
        await _writeAtomically(gitignore, [...?original, ...append]);
        run.onUndo(() async {
          if (original == null) {
            if (await gitignore.exists()) await gitignore.delete();
          } else {
            await _writeAtomically(gitignore, original);
          }
        });
        run.done(const ['.gitignore']);
      } else {
        run.skipped(
          plan.request.ignoreOkfLock
              ? '.gitignore already lists the okf lock file.'
              : 'The request leaves .gitignore unchanged.',
        );
      }

      run.start(AdoptionStep.host, cancel);
      if (hostStep != null) {
        await hostStep();
        run.done();
      } else {
        run.skipped('The host gave no step.');
      }
    } on Object catch (error) {
      run.fail(error);
      await run.undo();
      rethrow;
    }
    for (final backup in backups) {
      try {
        await backup.delete(recursive: true);
      } on FileSystemException {
        // Named as an interrupted write's copy, so the next get prunes it.
      }
    }
  }

  /// The profile step: moves each skill directory applying replaces aside
  /// into [backups], then writes the lock and skills through the resolver.
  /// Its undo deletes what it wrote and moves the replaced directories
  /// back, each part on its own, so one that fails does not stop the rest.
  Future<void> _installProfile(
    KnowledgeAdoptionPlan plan,
    _Run run,
    List<Directory> backups,
  ) async {
    final root = plan.projectRoot;
    final resolution = plan._resolution;
    final written = [
      for (final id in resolution.skillFiles.keys)
        ...ProfileSkills.directories(id),
    ];
    final createdRoots = [
      for (final directory in const [
        '.claude',
        '.claude/skills',
        '.agents',
        '.agents/skills',
      ])
        if (await FileSystemEntity.type(
              _native(root, directory),
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound)
          directory,
    ];
    run.onUndo(() async {
      for (final directory in createdRoots.reversed) {
        await _deleteIfEmpty(Directory(_native(root, directory)));
      }
    });
    final present = [
      for (final directory in written)
        if (await FileSystemEntity.type(
              _native(root, directory),
              followLinks: false,
            ) ==
            FileSystemEntityType.directory)
          directory,
    ];
    final saved = <String>{};
    for (final directory in present) {
      final original = Directory(_native(root, directory));
      // Named as ProfileSkills names a replaced copy, so a get after a
      // crash prunes it; the resolver here prunes nothing.
      final backup = Directory(
        p.join(
          original.parent.path,
          '.${p.basename(original.path)}.old-${_stamp()}',
        ),
      );
      await original.rename(backup.path);
      backups.add(backup);
      saved.add(directory);
      run.onUndo(() async {
        if (await backup.exists()) await backup.rename(original.path);
        backups.remove(backup);
      });
    }
    run.onUndo(() async {
      for (final directory in written) {
        final installed = Directory(_native(root, directory));
        // A directory that was there and is not saved aside is the
        // original: the step failed before moving it.
        if ((!present.contains(directory) || saved.contains(directory)) &&
            await installed.exists()) {
          await installed.delete(recursive: true);
        }
      }
    });
    final lock = File(p.join(root, 'wayfinder.lock'));
    run.onUndo(() => _deleteIfHolds(lock, utf8.encode(resolution.lockText)));
    await applyCandidateResolution(resolver, resolution);
    run.done(['wayfinder.lock', ...written]);
  }

  /// Files a host may want adoption to write that it never does.
  static const _neverWritten = {'AGENTS.md', 'CLAUDE.md', '.mcp.json'};

  static String _dataDirectoryOf(WayfinderProfileResolver resolver) =>
      p.normalize(resolver.dataDirectory.absolute.path);

  /// The bundle's mode, adding a conflict for what stops either.
  static Future<AdoptionBundleMode> _bundleMode(
    String projectRoot,
    String bundle,
    AdoptionRequest request,
    List<AdoptionConflict> conflicts,
  ) async {
    final segments = p.posix.split(bundle);
    for (var index = 1; index <= segments.length; index++) {
      final path = p.posix.joinAll(segments.take(index));
      final native = _native(projectRoot, path);
      switch (await FileSystemEntity.type(native, followLinks: false)) {
        case FileSystemEntityType.notFound:
          return AdoptionBundleMode.seed;
        case FileSystemEntityType.directory:
          if (index < segments.length) continue;
          // okf keeps only its lock file in a bundle it has emptied.
          if (await Directory(native)
              .list(followLinks: false)
              .every(
                (entity) =>
                    entity is File &&
                    p.basename(entity.path) == okfBundleLockFileName,
              )) {
            return AdoptionBundleMode.seed;
          }
          if (request.bindExisting) return AdoptionBundleMode.bind;
          conflicts.add(
            AdoptionConflict(
              'bundle-exists',
              path,
              '$path already holds files. Bind the existing bundle instead, '
                  'or choose another bundle directory.',
            ),
          );
          return AdoptionBundleMode.seed;
        case FileSystemEntityType.link:
          conflicts.add(
            AdoptionConflict(
              'bundle-link',
              path,
              '$path is a symbolic link; adoption does not write through '
                  'one.',
            ),
          );
          return AdoptionBundleMode.seed;
        default:
          conflicts.add(
            AdoptionConflict(
              'bundle-not-directory',
              path,
              '$path exists and is not a directory.',
            ),
          );
          return AdoptionBundleMode.seed;
      }
    }
    return AdoptionBundleMode.seed;
  }

  /// The seeded bundle: the root files, [concepts], and, with any concept,
  /// every index the chain's generated-index rules expect, as
  /// `validate --fix` writes it once OKF passes.
  static ({Map<String, String> files, OkfBundleLoadResult loaded}) _seed(
    String bundleRoot,
    SelectedProfile selection,
    Map<String, String> concepts, {
    required String log,
  }) {
    final indexes = {
      'index.md': KnowledgeSeeds.rootIndex(
        okfVersion: selection.profile.okfRelease,
      ),
    };
    final logs = {'log.md': log};
    final documents = <String, OkfDocument>{};
    for (final MapEntry(key: path, value: text) in concepts.entries) {
      try {
        documents[path] = OkfDocument.parse(text, sourcePath: path);
      } on FormatException catch (error) {
        throw _invalid(
          'Seed concept $path is not an OKF document: ${error.message}',
        );
      }
    }
    OkfBundleLoadResult load() {
      try {
        final bundle = OkfBundle.fromDocuments(
          documents,
          indexes: indexes,
          logs: logs,
        );
        return OkfBundleLoadResult(
          rootPath: bundleRoot,
          bundle: bundle,
          documents: documents,
          indexes: indexes,
          logs: logs,
          assets: const [],
          report: OkfReport(),
        );
      } on ArgumentError catch (error) {
        throw _invalid('Seed concepts are not a bundle: ${error.message}');
      }
    }

    var loaded = load();
    if (documents.isNotEmpty && loaded.validate().isConformant) {
      final generated = const ProfileProjection().generatedFiles(
        selection,
        loaded,
      );
      if (generated != null && generated.isNotEmpty) {
        indexes.addAll(generated);
        loaded = load();
      }
    }
    return (files: {...indexes, ...logs, ...concepts}, loaded: loaded);
  }

  /// The planned `.gitignore` file and the bytes applying appends, or nulls
  /// when nothing is appended.
  static Future<(AdoptionFile?, List<int>?)> _gitignore(
    String projectRoot,
    String bundle,
    AdoptionRequest request,
    List<AdoptionConflict> conflicts,
  ) async {
    if (!request.ignoreOkfLock) return (null, null);
    final line = KnowledgeSeeds.okfLockIgnore(bundle: bundle);
    final file = File(p.join(projectRoot, '.gitignore'));
    switch (await FileSystemEntity.type(file.path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        final append = utf8.encode('$line\n');
        return (
          _file(
            '.gitignore',
            AdoptionFileKind.gitignore,
            AdoptionFileAction.create,
            append,
            content: '$line\n',
          ),
          append,
        );
      case FileSystemEntityType.file:
        final bytes = await file.readAsBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        if (_ignoresOkfLock(text, line)) return (null, null);
        final newline = text.contains('\r\n') ? '\r\n' : '\n';
        final appended =
            '${text.isEmpty || text.endsWith('\n') ? '' : newline}'
            '$line$newline';
        final append = utf8.encode(appended);
        return (
          _file(
            '.gitignore',
            AdoptionFileKind.gitignore,
            AdoptionFileAction.append,
            [...bytes, ...append],
            content: appended,
          ),
          append,
        );
      default:
        conflicts.add(
          const AdoptionConflict(
            'gitignore-not-file',
            '.gitignore',
            '.gitignore exists and is not a regular file, so adoption cannot '
                'add the okf lock file to it.',
          ),
        );
        return (null, null);
    }
  }

  /// Whether [text] lists the okf lock [line] already: as the line itself,
  /// anchored, or as `.okf.lock` at any depth, with no later `!` line that
  /// re-includes one of those. Other patterns are not matched, so a
  /// `.gitignore` that ignores the file through one gains a redundant line,
  /// never a missing one.
  static bool _ignoresOkfLock(String text, String line) {
    final names = {
      line,
      '/$line',
      okfBundleLockFileName,
      '**/$okfBundleLockFileName',
    };
    var listed = false;
    for (final raw in const LineSplitter().convert(text)) {
      // Git ignores a pattern's trailing spaces, not its leading ones.
      final pattern = raw.trimRight();
      if (names.contains(pattern)) {
        listed = true;
      } else if (pattern.startsWith('!') &&
          names.contains(pattern.substring(1))) {
        listed = false;
      }
    }
    return listed;
  }

  /// The planned files of one skill, in each of its directories: the marker
  /// with its text, then every file by digest.
  static Future<List<AdoptionFile>> _skillFiles(
    String projectRoot,
    LockedPackage package,
    List<SkillFile> files,
  ) async => [
    for (final directory in ProfileSkills.directories(package.id))
      if (await Directory(_native(projectRoot, directory)).exists()
          case final exists)
        for (final file in [
          (
            path: ProfileSkills.marker,
            bytes: utf8.encode(ProfileSkills.markerText(package.revision)),
            executable: false,
          ),
          ...files.sortedBy((file) => file.path),
        ])
          _file(
            '$directory/${file.path}',
            AdoptionFileKind.skill,
            exists ? AdoptionFileAction.replace : AdoptionFileAction.create,
            file.bytes,
            content: file.path == ProfileSkills.marker
                ? utf8.decode(file.bytes)
                : null,
          ),
  ];

  static AdoptionFile _file(
    String path,
    AdoptionFileKind kind,
    AdoptionFileAction action,
    List<int> bytes, {
    String? content,
  }) => AdoptionFile(
    path: path,
    kind: kind,
    action: action,
    sha256: sha256.convert(bytes).toString(),
    size: bytes.length,
    content: content,
  );

  /// Stages the seeded bundle as a hidden sibling and renames it into
  /// place, creating missing parent directories; [onUndo] gains what removes
  /// each again. A bundle directory that exists is empty or holds only
  /// okf's lock file, which moves into the new bundle and back on undo.
  static Future<void> _writeBundle(
    KnowledgeAdoptionPlan plan,
    void Function(Future<void> Function() action) onUndo,
  ) async {
    final root = plan.projectRoot;
    final segments = p.posix.split(plan.bundle);
    for (var index = 1; index < segments.length; index++) {
      final parent = Directory(
        _native(root, p.posix.joinAll(segments.take(index))),
      );
      if (await parent.exists()) continue;
      await parent.create();
      onUndo(() => _deleteIfEmpty(parent));
    }
    final target = Directory(_native(root, plan.bundle));
    final staged = Directory(
      p.join(
        target.parent.path,
        '.${p.basename(target.path)}.adoption-${_stamp()}',
      ),
    );
    final existed = await target.exists();
    final lock = File(p.join(target.path, okfBundleLockFileName));
    final keepsLock = existed && await lock.exists();
    final stagedLock = File(p.join(staged.path, okfBundleLockFileName));
    await staged.create();
    try {
      for (final MapEntry(key: path, value: bytes)
          in plan._bundleFiles.entries) {
        final file = File(p.joinAll([staged.path, ...p.posix.split(path)]));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      try {
        if (keepsLock) await lock.rename(stagedLock.path);
        // delete refuses a directory that is not empty.
        if (existed) await target.delete();
        await staged.rename(target.path);
      } on Object {
        if (existed) {
          await target.create();
          if (await stagedLock.exists()) await stagedLock.rename(lock.path);
        }
        rethrow;
      }
      onUndo(() async {
        if (!existed) {
          if (await target.exists()) await target.delete(recursive: true);
          return;
        }
        await target.create();
        await for (final entity in target.list(followLinks: false)) {
          if (keepsLock && p.basename(entity.path) == okfBundleLockFileName) {
            continue;
          }
          await entity.delete(recursive: true);
        }
      });
    } on Object {
      if (await staged.exists()) await staged.delete(recursive: true);
      rethrow;
    }
  }

  static String _bundlePath(String bundle) {
    final normalized = p.posix.normalize(bundle);
    if (bundle.contains(r'\') ||
        p.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized == '.' ||
        p.posix
            .split(normalized)
            .any((segment) => segment == '..' || segment == '.git')) {
      throw _invalid(
        'Bundle $bundle must be a directory inside the project, as a '
        'relative POSIX path.',
      );
    }
    return normalized;
  }

  static Map<String, String> _concepts(List<AdoptionSeedConcept> concepts) {
    final result = SplayTreeMap<String, String>();
    for (final concept in concepts) {
      final path = concept.path;
      final name = p.posix.basename(path);
      if (path.contains(r'\') ||
          p.posix.isAbsolute(path) ||
          p.posix.normalize(path) != path ||
          path.split('/').any((segment) => segment == '..') ||
          !name.endsWith('.md') ||
          name == 'index.md' ||
          name == 'log.md') {
        throw _invalid(
          'Seed concept $path must be a bundle-relative POSIX path to a '
          'Markdown file other than index.md or log.md.',
        );
      }
      if (result.containsKey(path)) {
        throw _invalid('Seed concept $path is given twice.');
      }
      result[path] = concept.text;
    }
    return result;
  }

  /// The `wayfinder.json` text that binds [id] from the request's source at
  /// [ref] and [path], refusing as `adoption-invalid` a request that cannot
  /// be one.
  static String _configuration(
    AdoptionRequest request,
    String bundle, {
    required ProfileId id,
    required String ref,
    required String path,
  }) {
    final configuration = KnowledgeSeeds.configuration(
      profile: id.value,
      git: request.source.git,
      ref: ref,
      path: path,
      bundle: bundle,
      vocabulary: request.vocabulary,
    );
    try {
      WayfinderProjectConfig.parse(configuration);
    } on WayfinderConfigException catch (error) {
      // Without a requested id, name the entry as `<id>`, not the stand-in.
      throw _invalid(
        request.profile == null
            ? error.message
                  .replaceAll('/profiles/$_anyProfile/', '/profiles/<id>/')
                  .replaceAll('profiles.$_anyProfile.', 'profiles.<id>.')
            : error.message,
      );
    }
    return configuration;
  }

  /// Stands in for a Profile id or a commit the request leaves to the
  /// source, while the rest of the request is checked before any Git.
  static final _anyProfile = ProfileId.parse('profile');
  static final _anyCommit = '0' * 40;

  /// The request's host inputs, normalized, once each and in path order.
  static List<String> _hostInputs(List<String> paths) {
    final result = SplayTreeSet<String>();
    for (final path in paths) {
      final normalized = p.posix.normalize(path);
      // `..` is judged on the path as given. Normalizing first would remove
      // it before the later symlink walk, so `link/../AGENTS.md` would be
      // recorded as `AGENTS.md` when `link` points outside the project.
      if (path.contains(r'\') ||
          p.posix.isAbsolute(normalized) ||
          RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
          normalized == '.' ||
          p.posix.split(path).contains('..') ||
          AdoptionInputs.inGit(normalized)) {
        throw _invalid(
          'Host input $path must be a path inside the project, as a relative '
          'POSIX path outside .git.',
        );
      }
      result.add(normalized);
    }
    return List.unmodifiable(result);
  }

  static WayfinderException _invalid(String message) =>
      WayfinderException('adoption-invalid', message);

  static String _native(String root, String path) =>
      p.joinAll([root, ...p.posix.split(path)]);

  static String _stamp() => '$pid-${DateTime.now().microsecondsSinceEpoch}';

  static Future<void> _writeAtomically(File file, List<int> bytes) async {
    final temp = File('${file.path}.adoption-${_stamp()}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  /// Deletes [file] when it still holds [bytes], so undoing never removes
  /// what another writer put there since.
  static Future<void> _deleteIfHolds(File file, List<int> bytes) async {
    final current = await _readBytes(file);
    if (current != null && const ListEquality<int>().equals(current, bytes)) {
      await file.delete();
    }
  }

  static Future<void> _deleteIfEmpty(Directory directory) async {
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }

  static Future<List<int>?> _readBytes(File file) async {
    try {
      return await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }
}

/// The steps of one [KnowledgeAdoption.apply]: what each reported, what
/// undoes each, and the listener that hears each report as it happens.
final class _Run {
  _Run(this._listener);

  final void Function(AdoptionStepReport report)? _listener;

  /// The step running, or the last that ran.
  AdoptionStep step = AdoptionStep.check;

  /// Each step's report so far, in step order.
  final records = <_StepRecord>[];
  final _undo = <({AdoptionStep step, Future<void> Function() action})>[];
  final _undoFailures = <({AdoptionStep step, String failure})>[];
  bool _failed = false;

  /// Starts [next]: reports it started, then checks [cancel].
  void start(AdoptionStep next, WayfinderCancellation? cancel) {
    step = next;
    _listener?.call(AdoptionStepReport(next, AdoptionStepOutcome.started));
    throwIfCancelled(cancel);
  }

  void done([List<String> paths = const [], String? message]) =>
      _end(_StepRecord(step, AdoptionStepOutcome.done, paths, message));

  void skipped(String message) =>
      _end(_StepRecord(step, AdoptionStepOutcome.skipped, const [], message));

  /// Records how the running step ended, then reports it; what the listener
  /// throws fails the step, except for the host step's `done`: the host's
  /// writes are in place and adoption cannot undo them, so that report is
  /// told as a failure is.
  void _end(_StepRecord record) {
    records.add(record);
    if (record.step == AdoptionStep.host &&
        record.outcome == AdoptionStepOutcome.done) {
      _tell(record.report);
    } else {
      _listener?.call(record.report);
    }
  }

  /// Records that the running step failed with [error], once. A step that
  /// had ended, when the listener threw for its end, is failed instead, and
  /// its writes are undone as its own.
  void fail(Object error) {
    if (_failed) return;
    _failed = true;
    records.removeWhere((record) => record.step == step);
    final record = _StepRecord(
      step,
      AdoptionStepOutcome.failed,
      const [],
      _messageOf(error),
      _codeOf(error),
    );
    records.add(record);
    _tell(record.report);
  }

  /// Registers what undoes part of the running step.
  void onUndo(Future<void> Function() action) =>
      _undo.add((step: step, action: action));

  /// Runs every registered undo once, last first: the failed step's own,
  /// then each finished step's, reporting that step `undone`, or
  /// `undo-failed` when one of its undos failed; a failure is recorded and
  /// the rest go on.
  Future<void> undo() async {
    final actions = <AdoptionStep, List<Future<void> Function()>>{};
    for (final (:step, :action) in _undo) {
      (actions[step] ??= []).add(action);
    }
    _undo.clear();
    Future<bool> undoStep(AdoptionStep step) async {
      var undone = true;
      for (final action in (actions.remove(step) ?? const []).reversed) {
        try {
          await action();
        } on Object catch (failure) {
          undone = false;
          _undoFailures.add((step: step, failure: '$failure'));
        }
      }
      return undone;
    }

    if (!await undoStep(step)) {
      final failed = records.last;
      records[records.length - 1] = _StepRecord(
        failed.step,
        AdoptionStepOutcome.undoFailed,
        failed.paths,
        failed.message,
        failed.code,
      );
      _tell(records.last.report);
    }
    for (var index = records.length - 1; index >= 0; index--) {
      final record = records[index];
      if (record.outcome != AdoptionStepOutcome.done ||
          record.step == AdoptionStep.check) {
        continue;
      }
      final undone = await undoStep(record.step);
      records[index] = _StepRecord(
        record.step,
        undone ? AdoptionStepOutcome.undone : AdoptionStepOutcome.undoFailed,
        record.paths,
      );
      _tell(records[index].report);
    }
    // Registered by no step that finished or failed: none is expected.
    for (final step in actions.keys.toList().reversed) {
      await undoStep(step);
    }
  }

  /// [error] as the failure of the failed step, with each step before it
  /// reported undone, or `undo-failed` when undoing it failed.
  KnowledgeAdoptionException failure(Object error) {
    final message = _messageOf(error);
    return KnowledgeAdoptionException(
      _codeOf(error),
      _undoFailures.isEmpty
          ? message
          : '$message Undoing the adoption also failed, so the '
                'project may hold part of the adoption: '
                '${[for (final (step: _, :failure) in _undoFailures) failure].join('; ')}',
      steps: List.unmodifiable([for (final record in records) record.report]),
      cause: error,
      changedPaths: error is _StaleInputs ? error.paths : const [],
    );
  }

  /// Reports a failure or an undo; what the listener throws is ignored,
  /// since apply already reports that failure.
  void _tell(AdoptionStepReport report) {
    try {
      _listener?.call(report);
    } on Object {
      // The failure being reported stands.
    }
  }

  static String _codeOf(Object error) =>
      error is WayfinderException ? error.code : 'adoption-failed';

  static String _messageOf(Object error) =>
      error is WayfinderException ? error.message : '$error';
}

final class _StepRecord {
  _StepRecord(
    this.step,
    this.outcome, [
    this.paths = const [],
    this.message,
    this.code,
  ]);

  final AdoptionStep step;
  final AdoptionStepOutcome outcome;
  final List<String> paths;
  final String? message;
  final String? code;

  AdoptionStepReport get report => AdoptionStepReport(
    step,
    outcome,
    paths: paths,
    message: message,
    code: code,
  );
}

/// `adoption-stale`: the project paths the check step found changed since
/// planning.
final class _StaleInputs extends WayfinderException {
  _StaleInputs(this.paths)
    : super(
        'adoption-stale',
        '${paths.join(', ')} changed after adoption was planned. Plan again.',
      );

  final List<String> paths;
}
