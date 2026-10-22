import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../diagnostics.dart';
import '../field_edges.dart';
import '../profile_finding.dart';
import '../project/cancellation.dart';
import '../project/exception.dart';
import '../project/profile_resolver.dart';
import '../rules/evaluate.dart';
import '../rules/facts.dart';
import '../rules/structure_builtins.dart' show withLfLineEndings;
import '../validation.dart';
import '../wayfinder_config.dart';
import 'knowledge_change.dart';
import 'knowledge_log.dart';
import 'knowledge_stamp.dart';

/// A change that cannot be described against the bundle, so there is no
/// candidate to judge. [code] is `bundle-missing`, `concept-exists`,
/// `concept-not-found`, `change-invalid`, `log-unwritable`, or
/// `fix-not-applied` for a `RegenerateIndexes` with no fixable rule to run.
final class KnowledgeChangeException extends WayfinderException {
  const KnowledgeChangeException(super.code, super.message);
}

/// `write-stale`: the bundle, or the `wayfinder.json` or `wayfinder.lock`
/// its selection came from, changed after `prepare`. Prepare again.
final class KnowledgeStaleWriteException extends WayfinderException {
  const KnowledgeStaleWriteException(String message)
    : super('write-stale', message);
}

/// `write-refused`: `commit` was given a plan that is not
/// [KnowledgeWritePlan.committable]. Nothing was written.
final class KnowledgeWriteRefusedException extends WayfinderException {
  KnowledgeWriteRefusedException(this.plan)
    : super('write-refused', _refusal(plan));

  final KnowledgeWritePlan plan;

  static String _refusal(KnowledgeWritePlan plan) {
    if (!plan.okf.isConformant) {
      final errors = [
        for (final finding in plan.okf.report.findings)
          if (finding.severity == OkfFindingSeverity.error)
            [finding.id.value, ?finding.location?.path].join(' '),
      ];
      return 'OKF refuses the candidate: ${errors.join(', ')}.';
    }
    final errors = [
      for (final finding in plan.introduced)
        if (finding.severity == OkfFindingSeverity.error)
          '${finding.id} ${finding.path}',
      for (final diagnostic in plan.introducedDiagnostics)
        if (diagnostic.isError) diagnostic.id,
    ];
    return 'The write would add ${errors.length} error(s): '
        '${errors.join(', ')}.';
  }
}

/// `write-failed`: the file system refused the write, such as a bundle the
/// process may not write, a `.okf.lock` that is not a regular file, or a
/// file that cannot be read or replaced. The message names the path and the
/// operating system's reason.
///
/// [partial] is false when nothing was written: `prepare` writes nothing,
/// and okf rolls a failed commit back. It is true only when that rollback
/// failed too, so the bundle may hold part of the write; review it with
/// Git, and repair generated indexes with `RegenerateIndexes`.
final class KnowledgeWriteFailedException extends WayfinderException {
  const KnowledgeWriteFailedException(String message, {this.partial = false})
    : super('write-failed', message);

  final bool partial;

  static KnowledgeWriteFailedException _of(FileSystemException error) {
    final reason = error.osError?.message;
    final path = error.path;
    return KnowledgeWriteFailedException(
      [
        error.message,
        if (reason != null && reason.isNotEmpty) ': $reason',
        if (path != null && path.isNotEmpty) ' ($path)',
        '.',
      ].join(),
    );
  }
}

/// One file a commit writes: its bundle-relative [path], the text the
/// bundle holds ([before], null for a new file), and the text it writes.
final class KnowledgeFileDiff {
  const KnowledgeFileDiff({
    required this.path,
    required this.before,
    required this.after,
  });

  final String path;
  final String? before;
  final String after;
}

/// What a commit wrote, in path order.
final class KnowledgeCommitResult {
  KnowledgeCommitResult({required Iterable<String> changedPaths})
    : changedPaths = List.unmodifiable(changedPaths);

  final List<String> changedPaths;
}

/// What a write's Profile assessment judges, all in memory: the bundle
/// ([base]) and okf's prepared candidate ([candidate]) as okf loaded them,
/// and the [selection] both are judged with.
///
/// It holds no file handle, lock or callback into the writer, so a host may
/// send it to another isolate and run [assess] there.
final class KnowledgeAssessmentInput {
  const KnowledgeAssessmentInput({
    required this.base,
    required this.candidate,
    required this.selection,
    this.validator = const ProfileValidator(),
  });

  final OkfBundleLoadResult base;
  final OkfBundleLoadResult candidate;
  final ProfileSelection selection;
  final ProfileValidator validator;

  /// Judges [base] and [candidate] with `ProfileValidator.validateLoaded`,
  /// and runs the base's rules even when OKF blocks it, so a write that
  /// repairs OKF is charged only with the findings it adds.
  ///
  /// Synchronous, and reads no bundle file and takes no lock; only the
  /// `path-targets-exist` builtin checks the disk, for a path target the
  /// loaded bundle does not hold. A Profile rule can be slow, so a host
  /// that needs a deadline runs this on an isolate it can kill.
  KnowledgeAssessment assess() {
    final baseResult = validator.validateLoaded(base, selection);
    return KnowledgeAssessment(
      base: baseResult,
      candidate: validator.validateLoaded(candidate, selection),
      baseFindings: switch ((baseResult.profile, selection)) {
        (Assessed(:final findings), _) => findings,
        (BlockedByOkf(), SelectedProfile(:final profile)) => evaluate(
          profile,
          BundleFacts.project(
            base,
            profile: profile,
            buildGraph: validator.buildGraph,
          ),
        ).findings,
        _ => const [],
      },
    );
  }
}

/// The verdicts [KnowledgeAssessmentInput.assess] reaches.
final class KnowledgeAssessment {
  KnowledgeAssessment({
    required this.base,
    required this.candidate,
    required Iterable<ProfileFinding> baseFindings,
  }) : baseFindings = List.unmodifiable(baseFindings);

  /// The bundle as `validate` reports it.
  final ProfileValidationResult base;

  /// The candidate as `validate` would report it after the commit.
  final ProfileValidationResult candidate;

  /// The Profile findings of the base's rules, even when OKF blocks the
  /// base; the candidate's findings are compared with these.
  final List<ProfileFinding> baseFindings;
}

/// Runs a write's Profile assessment for [KnowledgeWriter.prepare], which
/// calls it once per plan, after okf's shared claim on the bundle is
/// released, with what okf loaded and prepared in memory.
///
/// It returns what [KnowledgeAssessmentInput.assess] returns for [input].
/// The default runs that on the calling isolate. A host that must bound a
/// Profile's rules runs it on an isolate it kills at a deadline, or when
/// [cancel], the cancellation `prepare` was given, is cancelled; whatever
/// it throws, such as [WayfinderException.cancelled], `prepare` throws.
typedef KnowledgeAssessor =
    Future<KnowledgeAssessment> Function(
      KnowledgeAssessmentInput input,
      WayfinderCancellation? cancel,
    );

Future<KnowledgeAssessment> _assessHere(
  KnowledgeAssessmentInput input,
  WayfinderCancellation? cancel,
) async => input.assess();

/// A prepared write: the bundle as it stands, the candidate it would become,
/// and the verdict that decides whether [KnowledgeWriter.commit] writes it.
///
/// The OKF gate is the whole bundle, as okf judges every write: a candidate
/// okf refuses, even for a file the change does not touch, is not
/// committable. The Profile gate is a delta. A candidate Profile finding is
/// [preExisting] when the base reports one with the same rule id and path,
/// counted as a multiset, and [introduced] otherwise; the plan is not
/// committable when an introduced finding, or an error diagnostic the base
/// does not report, is an error. A caller that also requires a passing
/// gate checks [candidate]'s `gate`; one that requires a Profile to have
/// judged the write checks [assessed].
final class KnowledgeWritePlan {
  KnowledgeWritePlan._({
    required this.bundle,
    required this.change,
    required this.selection,
    required this.base,
    required this.candidate,
    required Iterable<KnowledgeFileDiff> diff,
    required Iterable<ProfileFinding> introduced,
    required Iterable<ProfileFinding> preExisting,
    required Iterable<EngineDiagnostic> introducedDiagnostics,
    required OkfPreparedChange? prepared,
    required _ProjectFiles projectFiles,
  }) : diff = List.unmodifiable(diff),
       introduced = List.unmodifiable(introduced),
       preExisting = List.unmodifiable(preExisting),
       introducedDiagnostics = List.unmodifiable(introducedDiagnostics),
       _prepared = prepared,
       _projectFiles = projectFiles;

  /// The bundle root, absolute and normalized.
  final String bundle;

  final KnowledgeChange change;

  /// The Profile selection both validations used.
  final ProfileSelection selection;

  /// The bundle as it stands, as `validate` reports it.
  final ProfileValidationResult base;

  /// The candidate, as `validate` would report it after [diff] is written,
  /// judged in memory from okf's prepared candidate.
  final ProfileValidationResult candidate;

  /// Each file the commit writes, in path order.
  final List<KnowledgeFileDiff> diff;

  /// Candidate Profile findings the base does not report.
  final List<ProfileFinding> introduced;

  /// Candidate Profile findings the base already reports.
  final List<ProfileFinding> preExisting;

  /// Candidate diagnostics the base does not report, by id and location.
  final List<EngineDiagnostic> introducedDiagnostics;

  final OkfPreparedChange? _prepared;
  final _ProjectFiles _projectFiles;

  List<String> get changedPaths => [for (final file in diff) file.path];

  /// okf's Spec judgment of the candidate.
  OkfSpecValidation get okf => candidate.okfValidation;

  /// Whether a Profile's rules judged the candidate. False when none could
  /// be selected, such as for a bundle with no `wayfinder.json`, or one
  /// whose Profile is unresolved or does not compose: the base and the
  /// candidate then carry the same diagnostics, so the plan is judged by
  /// OKF alone, and `validate` reports the committed bundle `NOT_ASSESSED`
  /// rather than `PASS`. Also false when okf refuses the candidate.
  bool get assessed => candidate.profile is Assessed;

  bool get committable =>
      _prepared != null &&
      !introduced.any(
        (finding) => finding.severity == OkfFindingSeverity.error,
      ) &&
      !introducedDiagnostics.any((diagnostic) => diagnostic.isError);
}

/// The one write path for a knowledge bundle: [prepare] builds the candidate
/// a change describes and judges it, [commit] writes exactly what was
/// judged.
///
/// [prepare] maps the change onto okf's change set and calls okf's
/// `prepare` with a reserved-file projection. For indexes, the projection
/// writes only the files whose text the selected Profile's fixable rules
/// generate differently for the base and for the candidate, with exactly
/// the generated text (`ProfileProjection.generatedFiles`), so an index the
/// change does not affect keeps its text even when it is stale. Without a
/// fixable rule, okf's own regeneration of the changed concept's ancestor
/// indexes stands. For the root log, it writes what [KnowledgeLog] names.
/// The candidate is then judged in memory by the [KnowledgeAssessor], with
/// `ProfileValidator.validateLoaded`, never read back from disk.
///
/// okf's bundle lock covers the file access: [prepare] holds a shared claim
/// while it reads the bundle and okf prepares the candidate, releases it
/// before the Profile assessment, and writes nothing; [commit] holds the
/// exclusive claim, and okf refuses a bundle that changed since [prepare].
/// Run every write of a process on the isolate that does its other okf
/// bundle I/O (ADR-0018); only the assessment may run elsewhere.
final class KnowledgeWriter {
  /// [resolver] selects the bundle's Profile when [prepare] is given no
  /// selection; [validator] generates the Profile's indexes and judges the
  /// base and the candidate; [assess] runs that judgment, by default on the
  /// calling isolate; [clock] dates stamps and log entries.
  KnowledgeWriter({
    this.resolver,
    this.validator = const ProfileValidator(),
    KnowledgeAssessor assess = _assessHere,
    DateTime Function() clock = DateTime.now,
  }) : _assess = assess,
       _clock = clock;

  final WayfinderProfileResolver? resolver;
  final ProfileValidator validator;
  final KnowledgeAssessor _assess;
  final DateTime Function() _clock;

  /// Prepares [change] to the bundle at [bundle], stamped with [stamp], and
  /// returns the plan [commit] writes. Writes nothing.
  ///
  /// The Profile is [selection], or [resolver]'s selection for the bundle
  /// as `validate` makes it. When the selection names its project file,
  /// [commit] also refuses the plan if that `wayfinder.json` or the
  /// `wayfinder.lock` beside it changed since.
  ///
  /// [cancel] is checked between steps and passed to the resolver and the
  /// assessor; a cancelled prepare throws [WayfinderException.cancelled].
  ///
  /// Throws [KnowledgeChangeException] for a change that cannot be
  /// described against the bundle, [KnowledgeStaleWriteException] when the
  /// bundle changed while it was read, [KnowledgeWriteFailedException] when
  /// the bundle cannot be locked or read, and [ArgumentError] for a change,
  /// stamp or log entry the writer cannot record as given.
  Future<KnowledgeWritePlan> prepare(
    String bundle,
    KnowledgeChange change, {
    required KnowledgeStamp stamp,
    KnowledgeLog logEntry = KnowledgeLog.lifecycle,
    ProfileSelection? selection,
    WayfinderCancellation? cancel,
  }) async {
    _check(change, stamp, logEntry);
    throwIfCancelled(cancel);
    try {
      return await _prepare(
        bundle,
        change,
        stamp: stamp,
        log: logEntry,
        selection: selection,
        cancel: cancel,
      );
    } on FileSystemException catch (error) {
      throw KnowledgeWriteFailedException._of(error);
    }
  }

  Future<KnowledgeWritePlan> _prepare(
    String bundle,
    KnowledgeChange change, {
    required KnowledgeStamp stamp,
    required KnowledgeLog log,
    required ProfileSelection? selection,
    required WayfinderCancellation? cancel,
  }) async {
    if (await FileSystemEntity.type(bundle) != FileSystemEntityType.directory) {
      throw KnowledgeChangeException(
        'bundle-missing',
        'Bundle $bundle is not a directory.',
      );
    }
    final _ProjectFiles projectFiles;
    final ProfileSelection chosen;
    if (selection != null) {
      chosen = selection;
      projectFiles = await _ProjectFiles.read(_configFile(selection));
    } else {
      // Read the project files before selecting, so a change between the
      // two makes the plan stale rather than pairing a new lock with an
      // old selection.
      projectFiles = await _ProjectFiles.read(await _boundConfigFile(bundle));
      chosen = await _select(bundle, cancel);
    }
    throwIfCancelled(cancel);
    final now = _clock();
    final applier = OkfBundleChangeApplier(clock: () => now);
    // okf may run a read action twice, so this one only reads and prepares;
    // the Profile assessment runs once, after the claim is released.
    final (:preparation, :prepared, :diff) = await OkfBundleLock.read(
      bundle,
      () async {
        throwIfCancelled(cancel);
        final preparation = _Preparation(change, chosen, log);
        final changes = await _changeSet(bundle, preparation, stamp, now);
        final OkfBundlePreparation prepared;
        try {
          prepared = await applier.prepare(
            bundle,
            changes,
            project: (input) => _project(input, preparation),
          );
        } on OkfBundleChangeException catch (error) {
          throw KnowledgeChangeException('change-invalid', error.message);
        } on OkfStalePreparedChangeException {
          throw const KnowledgeStaleWriteException(
            'The bundle changed while the write was prepared. Prepare it '
            'again.',
          );
        }
        return (
          preparation: preparation,
          prepared: prepared,
          diff: await _diff(preparation),
        );
      },
    );
    throwIfCancelled(cancel);
    final candidate = switch (prepared) {
      OkfPreparationReady(:final prepared) => prepared.candidate,
      OkfPreparationRefused(:final candidate) =>
        candidate ?? (throw StateError('okf refused without a candidate')),
    };
    final base = preparation.base!;
    final assessment = await _assess(
      KnowledgeAssessmentInput(
        base: base,
        candidate: candidate.toLoadResult(),
        selection: chosen,
        validator: validator,
      ),
      cancel,
    );
    throwIfCancelled(cancel);
    final (:introduced, :preExisting) = _split(
      assessment.baseFindings,
      assessment.candidate.findings,
    );
    return KnowledgeWritePlan._(
      bundle: base.rootPath,
      change: change,
      selection: chosen,
      base: assessment.base,
      candidate: assessment.candidate,
      diff: diff,
      introduced: introduced,
      preExisting: preExisting,
      introducedDiagnostics: _newDiagnostics(
        assessment.base.diagnostics,
        assessment.candidate.diagnostics,
      ),
      prepared: switch (prepared) {
        OkfPreparationReady(:final prepared) => prepared,
        OkfPreparationRefused() => null,
      },
      projectFiles: projectFiles,
    );
  }

  /// Writes [plan] under okf's exclusive bundle lock: exactly the bytes
  /// [prepare] judged, or nothing.
  ///
  /// [cancel] is checked before the lock is taken and again once it is
  /// held; a cancelled commit writes nothing, throws
  /// [WayfinderException.cancelled], and leaves the plan committable. Once
  /// okf starts writing, the commit runs to its end. Waiting for the lock
  /// itself cannot be cancelled: okf's lock blocks while another process
  /// holds the bundle.
  ///
  /// Throws [KnowledgeWriteRefusedException] for a plan that is not
  /// committable, [KnowledgeStaleWriteException] when the bundle, or the
  /// project file or lock the plan's selection came from, changed since
  /// [prepare], and [KnowledgeWriteFailedException] when the bundle cannot
  /// be locked or written. A plan commits once; committing it again throws
  /// a [StateError].
  Future<KnowledgeCommitResult> commit(
    KnowledgeWritePlan plan, {
    WayfinderCancellation? cancel,
  }) async {
    final prepared = plan._prepared;
    if (prepared == null || !plan.committable) {
      throw KnowledgeWriteRefusedException(plan);
    }
    throwIfCancelled(cancel);
    if (plan.diff.isEmpty) return KnowledgeCommitResult(changedPaths: []);
    try {
      return await OkfBundleLock.write(plan.bundle, () async {
        throwIfCancelled(cancel);
        if (!await plan._projectFiles.isCurrent()) {
          throw const KnowledgeStaleWriteException(
            'wayfinder.json or wayfinder.lock changed after the write was '
            'prepared. Prepare it again.',
          );
        }
        try {
          final result = await const OkfBundleChangeApplier().commit(prepared);
          return KnowledgeCommitResult(changedPaths: result.changedPaths);
        } on OkfStalePreparedChangeException {
          throw const KnowledgeStaleWriteException(
            'The bundle changed after the write was prepared. Prepare it '
            'again.',
          );
        }
      });
    } on FileSystemException catch (error) {
      throw KnowledgeWriteFailedException._of(error);
    } on OkfWriteRollbackException catch (error) {
      throw KnowledgeWriteFailedException(
        'The write failed (${error.writeError}) and so did its rollback '
        '(${error.rollbackErrors.join('; ')}); the bundle may hold part of '
        'it.',
        partial: true,
      );
    }
  }

  Future<ProfileSelection> _select(
    String bundle,
    WayfinderCancellation? cancel,
  ) async {
    final resolver =
        this.resolver ??
        (throw ArgumentError(
          'KnowledgeWriter.prepare needs a selection or a resolver.',
        ));
    final selection = await resolver.select(bundle);
    if (selection is UnselectedProfile &&
        await resolver.restoreCachedPackages(bundle, cancel: cancel) > 0) {
      return resolver.select(bundle);
    }
    return selection;
  }

  static String? _configFile(ProfileSelection selection) => switch (selection) {
    SelectedProfile(:final config?) => config.file,
    _ => null,
  };

  static Future<String?> _boundConfigFile(String bundle) async {
    try {
      return (await WayfinderProjectConfig.bind(bundle)).config.file;
    } on BundleBindingException {
      return null;
    }
  }

  /// The okf change set for [preparation]'s change, reading the concept it
  /// changes.
  Future<OkfBundleChangeSet> _changeSet(
    String root,
    _Preparation preparation,
    KnowledgeStamp stamp,
    DateTime now,
  ) async {
    final event = <String, Object?>{
      'by': stamp.by,
      'at': _instant(stamp.at ?? now),
    };
    Map<String, Object?> verification(OkfDocument current, OkfConceptId id) => {
      if (stamp.verifies) _verified: _withEvent(current, id, event),
    };
    switch (preparation.change) {
      case CreateConcept(:final id, :final frontmatter, :final body):
        if (await File(p.join(root, id.documentPath)).exists()) {
          throw KnowledgeChangeException(
            'concept-exists',
            'Concept ${id.value} already exists.',
          );
        }
        return OkfBundleChangeSet([
          OkfCreateConceptChange(
            id: id,
            document: OkfDocument(
              frontmatter: {
                ...frontmatter,
                _generated: event,
                if (stamp.verifies) _verified: event,
              },
              body: body,
            ),
          ),
        ]);
      case UpdateConcept(:final id, :final frontmatter, :final body):
        final current = await preparation.read(root, id);
        return OkfBundleChangeSet([
          OkfUpdateConceptChange(
            id: id,
            frontmatterChanges: {
              ...frontmatter,
              if (_changesContent(current, frontmatter, body))
                _generated: event,
              ...verification(current, id),
            },
            body: body,
          ),
        ]);
      case LinkConcepts(:final source, :final relationship):
        final current = await preparation.read(root, source);
        final fields = {
          ..._relationships(current, source, [relationship]),
          ...verification(current, source),
        };
        return OkfBundleChangeSet([
          if (fields.isNotEmpty)
            OkfUpdateConceptChange(id: source, frontmatterChanges: fields),
        ]);
      case DeprecateConcept(:final id, :final note, :final relationships):
        final current = await preparation.read(root, id);
        final fields = {
          ..._relationships(current, id, relationships),
          ...verification(current, id),
        };
        return OkfBundleChangeSet([
          OkfDeprecateConceptChange(id: id, note: note),
          if (fields.isNotEmpty)
            OkfUpdateConceptChange(id: id, frontmatterChanges: fields),
        ]);
      case RegenerateIndexes():
        return OkfBundleChangeSet(const []);
    }
  }

  /// The reserved files okf should write instead of its own.
  Map<String, String?> _project(
    OkfProjectionInput input,
    _Preparation preparation,
  ) {
    final base = input.base;
    preparation
      ..base = base
      ..changedFiles = input.changedFiles;
    if (preparation.target case (:final id, :final document, text: _)) {
      if (base.documents[id.documentPath]?.serialize() !=
          document.serialize()) {
        throw const KnowledgeStaleWriteException(
          'The bundle changed while the write was prepared. Prepare it again.',
        );
      }
    }
    final selection = preparation.selection;
    final projector = ProfileProjection(buildGraph: validator.buildGraph);
    final projection = <String, String?>{};
    String? unlessCurrent(String path, String text) =>
        withLfLineEndings(base.indexes[path]) == text ? null : text;
    if (preparation.change is RegenerateIndexes) {
      final files = switch (selection) {
        SelectedProfile() => projector.generatedFiles(selection, base),
        UnselectedProfile() => null,
      };
      if (files == null) {
        throw KnowledgeChangeException('fix-not-applied', switch (selection) {
          SelectedProfile(:final profile) =>
            'Profile ${profile.selected.id} ${profile.selected.release} '
                'has no fixable rules.',
          UnselectedProfile() => 'No Profile was selected.',
        });
      }
      for (final MapEntry(key: path, value: text) in files.entries) {
        projection[path] = unlessCurrent(path, text);
      }
    } else if (selection is SelectedProfile) {
      final before = projector.generatedFiles(selection, base);
      final after = before == null
          ? null
          : projector.generatedFiles(selection, input.candidate.toLoadResult());
      if (before != null && after != null) {
        for (final path in {...before.keys, ...after.keys}) {
          if (before[path] == after[path]) continue;
          projection[path] = switch (after[path]) {
            final text? => unlessCurrent(path, text),
            null => null,
          };
        }
        // okf regenerates every ancestor index of a changed concept; one
        // whose generated text the change leaves alone keeps its own.
        for (final path in input.changedFiles.keys) {
          if (p.posix.basename(path) == _index) {
            projection.putIfAbsent(path, () => null);
          }
        }
      }
    }
    switch (suppliedLogEntries(preparation.log)) {
      case final entries?:
        final writes = _written(
          base,
          input.changedFiles,
          projection,
        ).keys.any((path) => path != _log);
        projection[_log] = writes
            ? _withEntries(base.logs[_log], [
                for (final entry in entries)
                  OkfLogEntry(
                    date: _isoDate(input.date),
                    action: entry.action,
                    description: entry.description,
                  ),
              ])
            : null;
      case null when identical(preparation.log, KnowledgeLog.none):
        projection[_log] = null;
      case null:
        // okf rewrites the whole log in its canonical form; keep its new
        // entries and the authored text around them.
        if (input.changedFiles[_log] case final rewritten?) {
          if (_addedEntries(base.logs[_log], rewritten, _isoDate(input.date))
              case final added?) {
            projection[_log] = _withEntries(base.logs[_log], added);
          }
        }
    }
    preparation.projection = projection;
    return projection;
  }

  /// Each file the commit writes, with the text the bundle holds, read
  /// under the shared claim.
  static Future<List<KnowledgeFileDiff>> _diff(_Preparation preparation) async {
    final base = preparation.base!;
    final files = _written(
      base,
      preparation.changedFiles,
      preparation.projection,
    );
    return [
      for (final path in files.keys.toList()..sort())
        KnowledgeFileDiff(
          path: path,
          before: await preparation.before(base, path),
          after: files[path]!,
        ),
    ];
  }

  static void _check(
    KnowledgeChange change,
    KnowledgeStamp stamp,
    KnowledgeLog log,
  ) {
    if (stamp.by.trim().isEmpty) {
      throw ArgumentError.value(stamp.by, 'stamp.by', 'must not be blank');
    }
    checkLog(log);
    final Map<String, Object?> fields = switch (change) {
      CreateConcept(:final frontmatter) ||
      UpdateConcept(:final frontmatter) => frontmatter,
      _ => const {},
    };
    final List<KnowledgeRelationship> relationships = switch (change) {
      LinkConcepts(:final relationship) => [relationship],
      DeprecateConcept(:final relationships) => relationships,
      _ => const [],
    };
    for (final key in const [_generated, _verified]) {
      if (fields.containsKey(key)) {
        throw ArgumentError.value(
          key,
          'frontmatter',
          'is written from the stamp',
        );
      }
    }
    for (final relationship in relationships) {
      if (relationship.relationship.trim().isEmpty ||
          relationship.resource.trim().isEmpty) {
        throw ArgumentError.value(
          relationship.toJson(),
          'relationship',
          'needs a nonblank name and resource',
        );
      }
    }
  }
}

/// What one run of [KnowledgeWriter.prepare] learns before okf's prepare
/// returns. okf's shared lock may run that action twice, so it starts
/// afresh each time.
final class _Preparation {
  _Preparation(this.change, this.selection, this.log);

  final KnowledgeChange change;
  final ProfileSelection selection;
  final KnowledgeLog log;

  /// The concept the change edits, as read before okf loaded the bundle.
  ({OkfConceptId id, OkfDocument document, String text})? target;

  OkfBundleLoadResult? base;
  Map<String, String> changedFiles = const {};
  Map<String, String?> projection = const {};

  /// Throws `concept-not-found` when [id] names no file, and lets any other
  /// read failure through for `prepare` to report as `write-failed`.
  Future<OkfDocument> read(String root, OkfConceptId id) async {
    final file = File(p.join(root, id.documentPath));
    if (!await file.exists()) {
      throw KnowledgeChangeException(
        'concept-not-found',
        'Concept ${id.value} does not exist.',
      );
    }
    final String text;
    try {
      // `readAsString` reports a decoding failure as a FileSystemException,
      // so decode the bytes here.
      text = utf8.decode(await file.readAsBytes());
    } on FormatException {
      throw KnowledgeChangeException(
        'change-invalid',
        'Concept ${id.value} is not UTF-8 text.',
      );
    }
    final OkfDocument document;
    try {
      document = OkfDocument.parse(text, sourcePath: id.documentPath);
    } on OkfDocumentException catch (error) {
      throw KnowledgeChangeException(
        'change-invalid',
        'Concept ${id.value} cannot be parsed: ${error.message}',
      );
    }
    target = (id: id, document: document, text: text);
    return document;
  }

  /// The text [path] holds in the base, read under the shared claim.
  Future<String?> before(OkfBundleLoadResult base, String path) async {
    final name = p.posix.basename(path);
    if (name == _index) return base.indexes[path];
    if (name == _log) return base.logs[path];
    if (target case (
      :final id,
      :final text,
      document: _,
    ) when id.documentPath == path) {
      return text;
    }
    final file = File(p.join(base.rootPath, path));
    return await file.exists() ? file.readAsString() : null;
  }
}

/// The `wayfinder.json` a selection came from and the `wayfinder.lock`
/// beside it, by digest; empty for a selection built by hand.
final class _ProjectFiles {
  const _ProjectFiles(this._digests);

  static Future<_ProjectFiles> read(String? config) async {
    if (config == null) return const _ProjectFiles({});
    final paths = [config, p.join(p.dirname(config), 'wayfinder.lock')];
    return _ProjectFiles({for (final path in paths) path: await _digest(path)});
  }

  final Map<String, String?> _digests;

  Future<bool> isCurrent() async {
    for (final MapEntry(key: path, value: digest) in _digests.entries) {
      if (await _digest(path) != digest) return false;
    }
    return true;
  }

  static Future<String?> _digest(String path) async {
    try {
      return sha256.convert(await File(path).readAsBytes()).toString();
    } on FileSystemException {
      return null;
    }
  }
}

const _index = 'index.md';
const _log = 'log.md';
const _generated = 'generated';
const _verified = 'verified';

/// The files okf writes for [changed] once [projection] applies, as
/// okf's `prepare` combines them: a null text, or one equal to the base's,
/// keeps the base file.
Map<String, String> _written(
  OkfBundleLoadResult base,
  Map<String, String> changed,
  Map<String, String?> projection,
) {
  final files = Map.of(changed);
  for (final MapEntry(key: path, value: text) in projection.entries) {
    if (text == null || text == (base.indexes[path] ?? base.logs[path])) {
      files.remove(path);
    } else {
      files[path] = text;
    }
  }
  return files;
}

/// Whether the update changes what `generated` dates: the body, `title`,
/// `description` or `type`.
bool _changesContent(
  OkfDocument current,
  Map<String, Object?> fields,
  String? body,
) {
  for (final key in const ['type', 'title', 'description']) {
    if (fields.containsKey(key) &&
        !const DeepCollectionEquality().equals(
          fields[key],
          current.frontmatter[key],
        )) {
      return true;
    }
  }
  String canonical(String text) =>
      OkfDocument(body: text, hasFrontmatter: false).serialize();
  return body != null && canonical(body) != canonical(current.body);
}

/// The `relationships` field with [additions] appended, or nothing when
/// every one is there already.
Map<String, Object?> _relationships(
  OkfDocument current,
  OkfConceptId id,
  Iterable<KnowledgeRelationship> additions,
) {
  final value = current.frontmatter[relationshipsLinkField.key];
  if (value != null && value is! List) {
    throw KnowledgeChangeException(
      'change-invalid',
      'Concept ${id.value} declares ${relationshipsLinkField.key} that are '
          'not a list.',
    );
  }
  final entries = [...?value as List?];
  final before = entries.length;
  for (final addition in additions) {
    if (!entries.any(addition.sameAs)) entries.add(addition.toJson());
  }
  return entries.length == before
      ? const {}
      : {relationshipsLinkField.key: entries};
}

/// The concept's `verified` events with [event] appended; OKF reads a bare
/// mapping as one event.
Object _withEvent(
  OkfDocument current,
  OkfConceptId id,
  Map<String, Object?> event,
) => switch (current.frontmatter[_verified]) {
  null => event,
  final List<Object?> events => [...events, event],
  final Map<Object?, Object?> single => [single, event],
  _ => throw KnowledgeChangeException(
    'change-invalid',
    'Concept ${id.value} records $_verified as neither a mapping nor a list.',
  ),
};

/// The root log with [added] recorded first. The entries are inserted into
/// [source] as lines in its own style, keeping every byte of the authored
/// history; when that cannot be done exactly, the log is okf's canonical
/// text of the same entries.
String _withEntries(String? source, List<OkfLogEntry> added) {
  if (source == null) {
    return OkfLogDocument(title: 'Log', entries: added).serialize();
  }
  final OkfLogDocument current;
  try {
    current = OkfLogDocument.parse(source, sourcePath: _log).toDocument();
  } on FormatException {
    throw _unwritableLog;
  } on StateError {
    throw _unwritableLog;
  }
  final expected = OkfLogDocument(
    title: current.title,
    entries: [...added, ...current.entries],
  );
  final inserted = _inserted(source, added);
  if (inserted != null) {
    final parsed = OkfLogDocument.parse(inserted, sourcePath: _log);
    if (parsed.issues.isEmpty &&
        parsed.title == expected.title &&
        _sameEntries(parsed.entries, expected.entries)) {
      return inserted;
    }
  }
  return expected.serialize();
}

/// [source] with [added], which share one date, inserted as lines in the
/// log's own style: first under that date's heading, or as a new section in
/// date order. Null when [added] spans dates.
String? _inserted(String source, List<OkfLogEntry> added) {
  final day = added.first.date;
  if (added.any((entry) => entry.date != day)) return null;
  final lines = source.split('\n');
  final cr = source.contains('\r\n') ? '\r' : '';
  final headings = [
    for (final (index, line) in lines.indexed)
      if (_dateHeading.firstMatch(line.trimRight()) case final match?)
        (index: index, date: match[1]!),
  ];
  bool blankAfter(int heading) =>
      heading + 1 < lines.length && lines[heading + 1].trim().isEmpty;
  final style = headings.isEmpty ? null : headings.first.index;
  final blank = style == null || blankAfter(style);
  final bullet =
      style != null &&
          lines
              .skip(style + 1)
              .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '*')
              .trimLeft()
              .startsWith('-')
      ? '-'
      : '*';
  final entries = [
    for (final entry in added)
      '$bullet **${entry.action}**: ${entry.description}$cr',
  ];
  final section = ['## $day$cr', if (blank) cr, ...entries];
  for (final (:index, :date) in headings) {
    final order = day.compareTo(date);
    if (order == 0) {
      lines.insertAll(index + (blankAfter(index) ? 2 : 1), entries);
      return lines.join('\n');
    }
    if (order > 0) {
      lines.insertAll(index, [...section, cr]);
      return lines.join('\n');
    }
  }
  // Older than every dated section, or the log has none: a last section.
  var end = lines.length;
  while (end > 0 && lines[end - 1].trim().isEmpty) {
    end--;
  }
  lines.replaceRange(end, lines.length, [cr, ...section, '']);
  return lines.join('\n');
}

/// The entries okf's lifecycle log [rewritten] adds to [source] under
/// [day], or null when they cannot be told apart from the entries it keeps.
List<OkfLogEntry>? _addedEntries(String? source, String rewritten, String day) {
  try {
    final after = OkfLogDocument.parse(rewritten, sourcePath: _log).entries;
    final before = source == null
        ? const <OkfLogEntry>[]
        : OkfLogDocument.parse(source, sourcePath: _log).toDocument().entries;
    final count = after.length - before.length;
    final start = after.indexWhere((entry) => entry.date == day);
    if (count <= 0 || start < 0 || start + count > after.length) return null;
    final added = after.sublist(start, start + count);
    final kept = [...after.take(start), ...after.skip(start + count)];
    if (added.any((entry) => entry.date != day) ||
        !_sameEntries(kept, before)) {
      return null;
    }
    return added;
  } on FormatException {
    return null;
  } on StateError {
    return null;
  }
}

bool _sameEntries(
  Iterable<OkfLogEntry> left,
  Iterable<OkfLogEntry> right,
) => const ListEquality<(String, String, String)>().equals(
  [for (final entry in left) (entry.date, entry.action, entry.description)],
  [for (final entry in right) (entry.date, entry.action, entry.description)],
);

final _dateHeading = RegExp(r'^## (\d{4}-\d{2}-\d{2})$');

const _unwritableLog = KnowledgeChangeException(
  'log-unwritable',
  'The root log.md cannot be rewritten without losing content. Repair it, '
      'then write again.',
);

({List<ProfileFinding> introduced, List<ProfileFinding> preExisting}) _split(
  Iterable<ProfileFinding> base,
  Iterable<ProfileFinding> candidate,
) {
  final remaining = <(String, String), int>{};
  for (final finding in base) {
    remaining.update(
      (finding.id, finding.path),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final introduced = <ProfileFinding>[];
  final preExisting = <ProfileFinding>[];
  for (final finding in candidate) {
    final key = (finding.id, finding.path);
    if ((remaining[key] ?? 0) > 0) {
      remaining[key] = remaining[key]! - 1;
      preExisting.add(finding);
    } else {
      introduced.add(finding);
    }
  }
  return (introduced: introduced, preExisting: preExisting);
}

List<EngineDiagnostic> _newDiagnostics(
  Iterable<EngineDiagnostic> base,
  Iterable<EngineDiagnostic> candidate,
) {
  final remaining = <(String, String?), int>{};
  for (final diagnostic in base) {
    remaining.update(
      (diagnostic.id, diagnostic.location?.path),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return [
    for (final diagnostic in candidate)
      if (remaining.update(
            (diagnostic.id, diagnostic.location?.path),
            (count) => count - 1,
            ifAbsent: () => -1,
          ) <
          0)
        diagnostic,
  ];
}

/// [time] in UTC to the second, as OKF writes an instant.
String _instant(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${_isoDate(utc)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}Z';
}

/// [date]'s calendar day as okf dates its log entries: from its own fields,
/// local or UTC as given.
String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
