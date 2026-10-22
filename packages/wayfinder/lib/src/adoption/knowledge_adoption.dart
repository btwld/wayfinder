import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../diagnostics.dart';
import '../project/cancellation.dart';
import '../project/exception.dart';
import '../project/file_lock.dart';
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
    required this.removedSkills,
    required this.conflicts,
    required this.agentInstructions,
    required this.validation,
    required AdoptionInputs inputs,
    required CandidateResolution resolution,
    required List<int> configuration,
    required Map<String, List<int>> bundleFiles,
    required List<int>? gitignoreAppend,
  }) : _inputs = inputs,
       _resolution = resolution,
       _configuration = configuration,
       _bundleFiles = bundleFiles,
       _gitignoreAppend = gitignoreAppend;

  final AdoptionRequest request;

  /// The absolute project directory.
  final String projectRoot;

  /// The bundle directory, relative to [projectRoot], as a POSIX path.
  final String bundle;

  /// Whether applying seeds a new bundle or binds the existing one.
  final AdoptionBundleMode mode;

  /// The Profile `wayfinder.json` binds, and the chain the lock pins.
  final AdoptionProfile profile;

  /// Every Git fetch adoption makes, in order. Planning made them, into the
  /// Profile cache only; applying fetches nothing.
  final List<ProfileFetch> fetches;

  /// Every file applying writes, in the order it writes them. Never
  /// `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or a hook.
  final List<AdoptionFile> files;

  /// Each Profile skill the chain ships, by id, with the project directories
  /// that hold it (`.claude/skills/<id>` and `.agents/skills/<id>`);
  /// `written` is false for one already installed at the locked commit.
  final List<MaterializedSkill> skills;

  /// Marked Profile skill directories of Profiles this project no longer
  /// locks, which applying deletes as `wayfinder get` would.
  final List<String> removedSkills;

  /// What stops applying. [KnowledgeAdoption.apply] refuses a plan with any,
  /// before writing anything.
  final List<AdoptionConflict> conflicts;

  /// The `### Knowledge bundle` block for the project's `AGENTS.md`, with
  /// the request's instruction lines. Adoption never writes it.
  final String agentInstructions;

  /// The bundle validated as applying leaves it, from the files above and
  /// the planned Profile. `PASS` is what completes adoption.
  final ProfileValidationResult validation;

  final AdoptionInputs _inputs;
  final CandidateResolution _resolution;
  final List<int> _configuration;
  final Map<String, List<int>> _bundleFiles;
  final List<int>? _gitignoreAppend;

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
    'removed_skills': removedSkills,
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
    required this.removedSkills,
    required this.validation,
    required this.agentInstructions,
  });

  final String projectRoot;
  final String bundle;

  /// Each step's report, in the order the steps ran.
  final List<AdoptionStepReport> steps;

  /// The project-relative files written, as the plan listed them.
  final List<String> written;

  /// The marked skill directories deleted.
  final List<String> removedSkills;

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
    'removed_skills': removedSkills,
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
/// process's okf bundle I/O (ADR-0018).
final class KnowledgeAdoption {
  KnowledgeAdoption({
    required this.resolver,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  /// Resolves the Profile and writes the lock and skills; its data
  /// directory also holds adoption's own lock.
  final WayfinderProfileResolver resolver;
  final DateTime Function() _clock;

  /// Reads the project, resolves the requested Profile, and returns what
  /// [apply] would write. Writes nothing in the project. Resolving may
  /// clone or refresh the Profile source in the Profile cache, unless the
  /// request is offline, which throws `fetch-required` instead. Throws
  /// `adoption-invalid` for a request that cannot describe an adoption,
  /// such as a malformed bundle path, source or seed concept; what the
  /// project holds is reported as [KnowledgeAdoptionPlan.conflicts].
  Future<KnowledgeAdoptionPlan> plan(
    AdoptionRequest request, {
    WayfinderCancellation? cancel,
  }) async {
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

    final inputs = await AdoptionInputs.read(projectRoot, bundle);
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

    final fetches = <ProfileFetch>[];
    var ref = request.source.ref;
    if (ref == null) {
      final resolved = await resolveDefaultBranch(
        resolver,
        projectRoot: projectRoot,
        git: git,
        offline: request.offline,
        cancel: cancel,
      );
      ref = resolved.commit;
      fetches.addAll(resolved.fetches);
    }
    final source = WayfinderProfileSource(
      git: git,
      ref: ref,
      path: p.posix.normalize(request.source.path),
    );
    final configuration = KnowledgeSeeds.configuration(
      profile: request.profile.value,
      git: source.git,
      ref: source.ref,
      path: source.path,
      bundle: bundle,
      vocabulary: request.vocabulary,
    );
    try {
      WayfinderProjectConfig.parse(configuration);
    } on WayfinderConfigException catch (error) {
      throw _invalid(error.message);
    }
    final configurationBytes = utf8.encode(configuration);
    final resolution = await planCandidateResolution(
      resolver,
      projectRoot: projectRoot,
      configuration: configurationBytes,
      offline: request.offline,
      cancel: cancel,
    );
    fetches.addAll(resolution.plan.fetches);
    if (resolution.skillProblems.escaping case final message?) {
      for (final root in await ProfileSkills.escaping(projectRoot)) {
        conflicts.add(AdoptionConflict('skill-root-escapes', root, message));
      }
    }
    for (final directory in resolution.skillProblems.unowned) {
      conflicts.add(
        AdoptionConflict(
          'skill-unowned',
          directory,
          '$directory already exists without a ${ProfileSkills.marker} '
              'marker, so adoption would not install the Profile skill there. '
              'Move it aside and plan again.',
        ),
      );
    }

    final composed = resolution.profiles[request.profile]!;
    final chain = ProfileLock(
      configurationSha256: '',
      packages: resolution.plan.packages,
    ).chainOf(request.profile)!;
    final profile = AdoptionProfile(
      id: request.profile,
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
            '$bundle fails OKF, so adoption does not bind it. Repair it with '
                '`okf validate $bundle` and plan again.',
          ),
        );
      }
    }
    final validation = const ProfileValidator().validateLoaded(
      loaded,
      selection,
    );

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
      removedSkills: resolution.plan.removedSkills,
      conflicts: List.unmodifiable(conflicts),
      agentInstructions: KnowledgeSeeds.knowledgeBundleInstructions(
        bundle: bundle,
        lines: request.instructionLines,
      ),
      validation: validation,
      inputs: inputs,
      resolution: resolution,
      configuration: configurationBytes,
      bundleFiles: Map.unmodifiable(bundleFiles),
      gitignoreAppend: gitignoreAppend,
    );
  }

  /// Writes [plan], one [AdoptionStep] at a time, then validates the
  /// bundle. Refuses a plan with conflicts (`adoption-conflict`), and one
  /// whose project files, bundle, skill directories or Profile cache changed
  /// since planning (`adoption-stale`, `resolution-stale`), before writing
  /// anything. Holds an adoption lock for the project in the resolver's data
  /// directory (`adoption-busy`), and the resolver's own project lock while
  /// it writes the lock and skills (`resolution-busy`).
  ///
  /// When a step fails, the steps before it are undone in reverse order and
  /// [KnowledgeAdoptionException] reports each step, so the project holds no
  /// partial bundle. Validation runs last and undoes nothing: a gate other
  /// than `PASS` returns a result that is not [KnowledgeAdoptionResult.complete].
  Future<KnowledgeAdoptionResult> apply(KnowledgeAdoptionPlan plan) async {
    final reports = <_StepRecord>[];
    final undo = <Future<void> Function()>[];
    final backups = <({Directory original, Directory backup})>[];
    var step = AdoptionStep.check;
    final root = plan.projectRoot;
    var removedSkills = const <String>[];
    WayfinderFileLock? held;
    try {
      if (plan.conflicts case [final first, ...final rest]) {
        throw WayfinderException(
          'adoption-conflict',
          '${first.message}'
              '${rest.isEmpty ? '' : ' The plan has ${rest.length} more '
                        'conflict${rest.length == 1 ? '' : 's'}.'}',
        );
      }
      held = await WayfinderFileLock.tryExclusive(await _adoptionLock(root));
      if (held == null) {
        throw WayfinderException(
          'adoption-busy',
          'Another adoption is writing $root. Plan again when it finishes.',
        );
      }
      final changed = (await AdoptionInputs.read(
        root,
        plan.bundle,
      )).changedSince(plan._inputs);
      if (changed.isNotEmpty) {
        throw WayfinderException(
          'adoption-stale',
          '${changed.join(', ')} changed after adoption was planned. Plan '
              'again.',
        );
      }
      await plan._resolution.checkCache();
      reports.add(_StepRecord(step, AdoptionStepOutcome.done));

      step = AdoptionStep.bundle;
      if (plan.mode == AdoptionBundleMode.seed) {
        await _writeBundle(plan, undo);
        reports.add(
          _StepRecord(step, AdoptionStepOutcome.done, [
            for (final path in plan._bundleFiles.keys) '${plan.bundle}/$path',
          ]),
        );
      } else {
        reports.add(
          _StepRecord(
            step,
            AdoptionStepOutcome.skipped,
            const [],
            'Bound the existing bundle without writing in it.',
          ),
        );
      }

      step = AdoptionStep.configuration;
      final configuration = File(p.join(root, 'wayfinder.json'));
      await _writeAtomically(configuration, plan._configuration);
      undo.add(() => _deleteIfHolds(configuration, plan._configuration));
      reports.add(
        _StepRecord(step, AdoptionStepOutcome.done, const ['wayfinder.json']),
      );

      step = AdoptionStep.profile;
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
      final present = {
        for (final directory in [...written, ...plan.removedSkills])
          if (await FileSystemEntity.type(
                _native(root, directory),
                followLinks: false,
              ) ==
              FileSystemEntityType.directory)
            directory,
      };
      final lock = File(p.join(root, 'wayfinder.lock'));
      undo.add(() async {
        await _deleteIfHolds(lock, utf8.encode(resolution.lockText));
        final saved = {
          for (final (:original, backup: _) in backups) original.path,
        };
        for (final directory in written) {
          final installed = Directory(_native(root, directory));
          // A directory that was there and is not saved aside is the
          // original: the step failed before moving it.
          if ((!present.contains(directory) ||
                  saved.contains(installed.path)) &&
              await installed.exists()) {
            await installed.delete(recursive: true);
          }
        }
        for (final (:original, :backup) in backups.reversed) {
          if (await backup.exists()) await backup.rename(original.path);
        }
        for (final directory in createdRoots.reversed) {
          await _deleteIfEmpty(Directory(_native(root, directory)));
        }
      });
      for (final directory in present) {
        final original = Directory(_native(root, directory));
        final backup = Directory(
          p.join(
            original.parent.path,
            '.${p.basename(original.path)}.adoption-${_stamp()}',
          ),
        );
        await original.rename(backup.path);
        backups.add((original: original, backup: backup));
      }
      await resolver.apply(resolution.plan);
      removedSkills = plan.removedSkills;
      reports.add(
        _StepRecord(step, AdoptionStepOutcome.done, [
          'wayfinder.lock',
          ...written,
          ...removedSkills,
        ]),
      );

      step = AdoptionStep.gitignore;
      if (plan._gitignoreAppend case final append?) {
        final gitignore = File(p.join(root, '.gitignore'));
        final original = await _readBytes(gitignore);
        await _writeAtomically(gitignore, [...?original, ...append]);
        undo.add(() async {
          if (original == null) {
            if (await gitignore.exists()) await gitignore.delete();
          } else {
            await _writeAtomically(gitignore, original);
          }
        });
        reports.add(
          _StepRecord(step, AdoptionStepOutcome.done, const ['.gitignore']),
        );
      } else {
        reports.add(
          _StepRecord(
            step,
            AdoptionStepOutcome.skipped,
            const [],
            plan.request.ignoreOkfLock
                ? '.gitignore already ignores the okf lock file.'
                : 'The request leaves .gitignore unchanged.',
          ),
        );
      }
    } on Object catch (error) {
      final undoFailures = <String>[];
      for (final action in undo.reversed) {
        try {
          await action();
        } on Object catch (failure) {
          undoFailures.add('$failure');
        }
      }
      final message = error is WayfinderException ? error.message : '$error';
      final steps = [
        for (final record in reports)
          record.outcome == AdoptionStepOutcome.done &&
                  record.step != AdoptionStep.check
              ? AdoptionStepReport(
                  record.step,
                  AdoptionStepOutcome.undone,
                  paths: record.paths,
                )
              : record.report,
        AdoptionStepReport(step, AdoptionStepOutcome.failed, message: message),
      ];
      throw KnowledgeAdoptionException(
        error is WayfinderException ? error.code : 'adoption-failed',
        undoFailures.isEmpty
            ? message
            : '$message Undoing the earlier steps also failed, so the '
                  'project may hold part of the adoption: '
                  '${undoFailures.join('; ')}',
        steps: List.unmodifiable(steps),
        cause: error,
      );
    } finally {
      await held?.release();
    }
    for (final (original: _, :backup) in backups) {
      try {
        await backup.delete(recursive: true);
      } on FileSystemException {
        // A hidden copy left behind is harmless; the next get ignores it.
      }
    }

    ProfileValidationResult? validation;
    try {
      validation = await validateWithProfileSources(
        p.joinAll([root, ...p.posix.split(plan.bundle)]),
        resolver: resolver,
      );
      reports.add(
        _StepRecord(
          AdoptionStep.validate,
          AdoptionStepOutcome.done,
          const [],
          'Gate ${validation.gate.wireValue}.',
        ),
      );
    } on Object catch (error) {
      reports.add(
        _StepRecord(
          AdoptionStep.validate,
          AdoptionStepOutcome.failed,
          const [],
          error is WayfinderException ? error.message : '$error',
        ),
      );
    }
    return KnowledgeAdoptionResult(
      projectRoot: root,
      bundle: plan.bundle,
      steps: List.unmodifiable([for (final record in reports) record.report]),
      written: List.unmodifiable([for (final file in plan.files) file.path]),
      removedSkills: removedSkills,
      validation: validation,
      agentInstructions: plan.agentInstructions,
    );
  }

  /// Files a host may want adoption to write that it never does.
  static const _neverWritten = {'AGENTS.md', 'CLAUDE.md', '.mcp.json'};

  Future<File> _adoptionLock(String projectRoot) async {
    final root = await Directory(projectRoot).resolveSymbolicLinks();
    return File(
      p.join(
        resolver.dataDirectory.path,
        'projects',
        '${sha256.convert(utf8.encode(root))}.adopt.lock',
      ),
    );
  }

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
          if (await Directory(native).list().isEmpty) {
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

  /// Whether a `.gitignore` pattern of [text] names the okf lock [line]
  /// already: the line itself, anchored, or `.okf.lock` at any depth.
  static bool _ignoresOkfLock(String text, String line) => const LineSplitter()
      .convert(text)
      .map((pattern) => pattern.trim())
      .any(
        (pattern) => {
          line,
          '/$line',
          okfBundleLockFileName,
          '**/$okfBundleLockFileName',
        }.contains(pattern),
      );

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
  /// place, creating missing parent directories; [undo] gains what removes
  /// each again.
  static Future<void> _writeBundle(
    KnowledgeAdoptionPlan plan,
    List<Future<void> Function()> undo,
  ) async {
    final root = plan.projectRoot;
    final segments = p.posix.split(plan.bundle);
    for (var index = 1; index < segments.length; index++) {
      final parent = Directory(
        _native(root, p.posix.joinAll(segments.take(index))),
      );
      if (await parent.exists()) continue;
      await parent.create();
      undo.add(() => _deleteIfEmpty(parent));
    }
    final target = Directory(_native(root, plan.bundle));
    final staged = Directory(
      p.join(
        target.parent.path,
        '.${p.basename(target.path)}.adoption-${_stamp()}',
      ),
    );
    await staged.create();
    try {
      for (final MapEntry(key: path, value: bytes)
          in plan._bundleFiles.entries) {
        final file = File(p.joinAll([staged.path, ...p.posix.split(path)]));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      // An empty bundle directory is replaced; delete refuses a full one.
      final empty = await target.exists();
      if (empty) await target.delete();
      try {
        await staged.rename(target.path);
      } on Object {
        if (empty) await target.create();
        rethrow;
      }
      undo.add(() async {
        if (await target.exists()) await target.delete(recursive: true);
        if (empty) await target.create();
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

final class _StepRecord {
  _StepRecord(this.step, this.outcome, [this.paths = const [], this.message]);

  final AdoptionStep step;
  final AdoptionStepOutcome outcome;
  final List<String> paths;
  final String? message;

  AdoptionStepReport get report =>
      AdoptionStepReport(step, outcome, paths: paths, message: message);
}
