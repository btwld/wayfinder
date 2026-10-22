import 'dart:io';
import 'dart:math';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import 'diagnostics.dart';
import 'profile_finding.dart';
import 'profile_package.dart';
import 'profile_rule_descriptors.dart';
import 'rules/evaluate.dart';
import 'rules/facts.dart';
import 'rules/profile.dart';
import 'rules/structure_builtins.dart' show withLfLineEndings;

enum OkfState {
  pass('PASS'),
  fail('FAIL');

  const OkfState(this.wireValue);
  final String wireValue;
}

enum ProfileState {
  pass('PASS'),
  fail('FAIL'),
  blockedByOkf('BLOCKED BY OKF'),
  notAssessed('NOT ASSESSED');

  const ProfileState(this.wireValue);
  final String wireValue;
}

/// What the resolver hands the validator: a Profile to assess, or why there
/// is none.
sealed class ProfileSelection {
  const ProfileSelection();
}

final class SelectedProfile extends ProfileSelection {
  /// Throws when a note is an error, so a selected run derives its gate
  /// from the assessment alone.
  SelectedProfile(
    this.profile, {
    this.config,
    this.commits = const {},
    Iterable<EngineDiagnostic> notes = const [],
  }) : notes = List.unmodifiable(notes) {
    if (this.notes.any((d) => d.isError)) {
      throw ArgumentError.value(notes, 'notes', 'cannot hold an error');
    }
  }

  final EffectiveProfile profile;

  /// The project file that bound the bundle; null for a selection built by
  /// hand, as in tests and authoring tools. Project-type notes point here.
  final ProjectFileLocation? config;

  /// The locked commit of each package in the chain; empty for a selection
  /// built by hand.
  final Map<ProfileId, String> commits;

  /// What selecting found that does not stop the assessment, such as a
  /// stale Profile skill. Never an error, so it cannot change the gate.
  final List<EngineDiagnostic> notes;
}

final class UnselectedProfile extends ProfileSelection {
  /// Throws unless [reasons] holds an error diagnostic, so an unselected run
  /// can never derive a PASS.
  UnselectedProfile(Iterable<EngineDiagnostic> reasons)
    : reasons = List.unmodifiable(reasons) {
    if (!this.reasons.any((d) => d.isError)) {
      throw ArgumentError.value(
        reasons,
        'reasons',
        'needs an error diagnostic',
      );
    }
  }

  final List<EngineDiagnostic> reasons;
}

/// What the Profile layer of a run did.
sealed class ProfileAssessment {
  const ProfileAssessment();
}

/// Every rule of [profile] ran against the bundle.
final class Assessed extends ProfileAssessment {
  Assessed(
    this.profile,
    Iterable<ProfileFinding> findings,
    Iterable<ProfileSummaryEntry>? summary, {
    this.commits = const {},
  }) : findings = List.unmodifiable(findings),
       summary = summary == null ? null : List.unmodifiable(summary);

  final EffectiveProfile profile;

  /// The locked commit of each package in the chain, when known.
  final Map<ProfileId, String> commits;

  /// In canonical okf order.
  final List<ProfileFinding> findings;

  /// What the assessment found that the Profile permits, in canonical order.
  /// Null unless an assessed package declares a note rule, so a Profile
  /// without one keeps its output shape.
  final List<ProfileSummaryEntry>? summary;

  String get release => profile.selected.release;
}

/// OKF failed, so no Profile rule ran. [profile] is the selection that
/// would have been assessed, when there was one, so reports still name it.
final class BlockedByOkf extends ProfileAssessment {
  const BlockedByOkf({this.profile, this.commits = const {}});

  final EffectiveProfile? profile;

  /// The locked commit of each package in the chain, when known.
  final Map<ProfileId, String> commits;
}

/// No Profile could be selected; an error diagnostic says why.
final class NotAssessed extends ProfileAssessment {
  const NotAssessed();
}

/// The single outcome of a run, under okf's exit-code contract.
enum GateState {
  pass('PASS', OkfExitCode.success),
  fail('FAIL', OkfExitCode.findings),
  incomplete('INCOMPLETE', OkfExitCode.usage);

  const GateState(this.wireValue, this.okfExitCode);
  final String wireValue;
  final OkfExitCode okfExitCode;

  int get exitCode => okfExitCode.value;
}

final class ProfileValidationResult {
  /// Throws when [profile] is [NotAssessed] without an error diagnostic: an
  /// unassessed run must never derive a PASS.
  ProfileValidationResult._(
    this.okfValidation,
    this.profile,
    Iterable<EngineDiagnostic> diagnostics, {
    Iterable<String>? fixed,
  }) : diagnostics = List.unmodifiable(diagnostics),
       fixed = fixed == null ? null : List.unmodifiable(fixed) {
    if (profile is NotAssessed && !this.diagnostics.any((d) => d.isError)) {
      throw ArgumentError.value(
        diagnostics,
        'diagnostics',
        'an unassessed Profile needs an error diagnostic',
      );
    }
  }

  final OkfSpecValidation okfValidation;
  final ProfileAssessment profile;

  /// The engine's reports about this run, in emission order.
  final List<EngineDiagnostic> diagnostics;

  /// Bundle-relative paths `--fix` wrote, in path order; null when no fix
  /// ran. Why a fix failed or did not run is a diagnostic.
  final List<String>? fixed;

  /// FAIL needs one witness; PASS needs a run that assessed everything.
  GateState get gate {
    if (!okfValidation.isConformant) return GateState.fail;
    if (findings.any((f) => f.severity == OkfFindingSeverity.error)) {
      return GateState.fail;
    }
    if (diagnostics.any((d) => d.isError)) return GateState.incomplete;
    return GateState.pass;
  }

  int get exitCode => gate.exitCode;

  OkfReport get okfReport => okfValidation.report;
  OkfState get okfState =>
      okfValidation.isConformant ? OkfState.pass : OkfState.fail;

  ProfileState get profileState => switch (profile) {
    Assessed(:final findings)
        when findings.any((f) => f.severity == OkfFindingSeverity.error) =>
      ProfileState.fail,
    Assessed() => ProfileState.pass,
    BlockedByOkf() => ProfileState.blockedByOkf,
    NotAssessed() => ProfileState.notAssessed,
  };

  /// The selected Profile, whether or not it was assessed.
  EffectiveProfile? get _selected => switch (profile) {
    Assessed(profile: final EffectiveProfile? profile) ||
    BlockedByOkf(profile: final EffectiveProfile? profile) => profile,
    NotAssessed() => null,
  };

  String? get profileRelease => _selected?.selected.release;

  ProfileId? get profileId => _selected?.selected.id;

  List<ProfileFinding> get findings => switch (profile) {
    Assessed(:final findings) => findings,
    _ => const [],
  };

  List<ProfileSummaryEntry>? get summary => switch (profile) {
    Assessed(:final summary) => summary,
    _ => null,
  };

  /// The selected packages, root ancestor first; empty when none was.
  List<ProfilePackage> get chain => _selected?.chain ?? const [];

  Map<String, Object?> toJson() => <String, Object?>{
    'okf': <String, Object?>{
      'state': okfState.wireValue,
      'report': okfReport.toJson(),
    },
    'profile': <String, Object?>{
      if (profile
          case Assessed(:final profile, :final commits) ||
              BlockedByOkf(profile: final profile?, :final commits)) ...{
        'id': profile.selected.id.value,
        'release': profile.selected.release,
        'chain': [
          for (final package in profile.chain)
            <String, Object>{
              'id': package.id.value,
              'release': package.release,
              'commit': ?commits[package.id],
            },
        ],
      },
      'state': profileState.wireValue,
      'findings': findings.map((finding) => finding.toJson()).toList(),
      if (summary case final summary?)
        'summary': summary.map((entry) => entry.toJson()).toList(),
    },
    'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
    if (fixed case final fixed?) 'fix': <String, Object?>{'written': fixed},
    'gate': <String, Object>{'state': gate.wireValue},
    'engine': <String, Object>{'okf': okfVersion},
  };

  Iterable<String> toTextLines() sync* {
    if (fixed case final fixed?) {
      for (final path in fixed) {
        yield 'Fix: wrote $path';
      }
      if (fixed.isEmpty &&
          !diagnostics.any((d) => d.code == DiagnosticCode.fixFailed)) {
        yield 'Fix: every generated file is current.';
      }
    }
    yield 'OKF: ${okfState.wireValue}';
    yield* okfReport.toTextLines();
    final errors = _countBySeverity(OkfFindingSeverity.error);
    final advisories = _countBySeverity(OkfFindingSeverity.advisory);
    yield 'OKF Report: $errors error(s), $advisories advisory(ies).';
    yield switch ((profileId, profileRelease)) {
      (final id?, final release?) =>
        'Profile $id $release: ${profileState.wireValue}',
      _ => 'Profile: ${profileState.wireValue}',
    };
    for (final finding in findings) {
      yield finding.toText();
    }
    if (summary case final summary? when summary.isNotEmpty) {
      yield 'Summary:';
      for (final entry in summary) {
        yield entry.toText();
      }
    }
    if (diagnostics.isNotEmpty) {
      yield 'Diagnostics:';
      for (final diagnostic in diagnostics) {
        yield diagnostic.toText();
      }
    }
    yield 'Gate: ${gate.wireValue}';
  }

  int _countBySeverity(OkfFindingSeverity severity) => okfReport.findings
      .where((finding) => finding.severity == severity)
      .length;
}

/// The JSON of a run that stopped before it had a result: only the
/// `wayfinder/internal-error` diagnostic and the gate it derives.
Map<String, Object?> internalErrorJson(String message) => <String, Object?>{
  'diagnostics': [
    EngineDiagnostic(DiagnosticCode.internalError, message).toJson(),
  ],
  'gate': <String, Object>{'state': GateState.incomplete.wireValue},
};

/// The failure validation reports when the chain of [id] does not compose.
({DiagnosticCode code, String message}) compositionFailure(
  ProfileId id,
  ProfileCompositionException error,
) => (
  code: DiagnosticCode.profileComposition,
  message: 'Profile $id: ${error.message}',
);

/// What a selected Profile's fixable rules generate for a bundle.
final class ProfileProjection {
  const ProfileProjection({this.buildGraph = OkfGraph.fromBundle});

  /// Builds the bundle's link graph, as [ProfileValidator.buildGraph] does.
  final OkfGraph Function(OkfBundle) buildGraph;

  /// Each bundle-relative path the chain's fixable rules generate, with its
  /// text: what `validate --fix` writes. Null when no rule in the chain is
  /// fixable. Reads only [loaded]; writes nothing.
  Map<String, String>? generatedFiles(
    SelectedProfile selection,
    OkfBundleLoadResult loaded,
  ) => fixes(
    selection.profile,
    BundleFacts.project(
      loaded,
      profile: selection.profile,
      buildGraph: buildGraph,
    ),
  );
}

final class ProfileValidator {
  const ProfileValidator({
    this.loader = const OkfBundleLoader(),
    this.buildGraph = OkfGraph.fromBundle,
  });

  final OkfBundleLoader loader;

  /// Builds the bundle's link graph; a throw becomes a
  /// `wayfinder/link-graph-unavailable` diagnostic.
  final OkfGraph Function(OkfBundle) buildGraph;

  /// Never throws for bundle content: what cannot be assessed is reported
  /// as a diagnostic. Reads only the bundle; [selection] carries everything
  /// known about the Profile. With [fix], first writes what
  /// [ProfileProjection.generatedFiles] returns, then validates the bundle
  /// again from disk. A fix that has something to write holds okf's
  /// exclusive bundle lock (`OkfBundleLock.write`) while it loads the bundle
  /// again, writes and validates; one with nothing to write takes no lock.
  Future<ProfileValidationResult> validate(
    String bundlePath,
    ProfileSelection selection, {
    bool fix = false,
  }) async {
    final loaded = await loader.inspect(bundlePath);
    if (!fix) return validateLoaded(loaded, selection);
    final unfixed = _fixNotApplied(loaded, selection);
    if (unfixed != null) return unfixed;
    final selected = selection as SelectedProfile;
    final files = ProfileProjection(
      buildGraph: buildGraph,
    ).generatedFiles(selected, loaded);
    if (files == null) {
      return _fixThenAssess(loaded.validate(), loaded, selected);
    }
    if (files.entries.every(
      (file) => withLfLineEndings(loaded.indexes[file.key]) == file.value,
    )) {
      return _assess(loaded.validate(), loaded, selected, fixed: const []);
    }
    return OkfBundleLock.write(loaded.rootPath, () async {
      final current = await loader.inspect(loaded.rootPath);
      return _fixNotApplied(current, selection) ??
          _fixThenAssess(current.validate(), current, selected);
    });
  }

  /// The result of a fix that cannot run on [loaded], or null when it can.
  ProfileValidationResult? _fixNotApplied(
    OkfBundleLoadResult loaded,
    ProfileSelection selection,
  ) {
    final validation = loaded.validate();
    final reason = switch (selection) {
      _ when !validation.isConformant => 'OKF failed.',
      UnselectedProfile() => 'No Profile was selected.',
      SelectedProfile() => null,
    };
    if (reason == null) return null;
    return _validateLoaded(
      loaded,
      selection,
      validation: validation,
      diagnostics: [EngineDiagnostic(DiagnosticCode.fixNotApplied, reason)],
    );
  }

  /// Validates a bundle okf already loaded, such as a candidate an authoring
  /// tool built in memory, against [selection]. Never throws for bundle
  /// content, and reads no bundle file from disk. Only the
  /// `path-targets-exist` builtin looks further, for a path target okf's
  /// graph cannot resolve: first in [loaded], so a candidate sees the files
  /// it adds, then on disk relative to the loaded `rootPath`, such as for a
  /// target that leaves the bundle.
  ProfileValidationResult validateLoaded(
    OkfBundleLoadResult loaded,
    ProfileSelection selection,
  ) => _validateLoaded(loaded, selection);

  ProfileValidationResult _validateLoaded(
    OkfBundleLoadResult loaded,
    ProfileSelection selection, {
    OkfSpecValidation? validation,
    List<EngineDiagnostic> diagnostics = const [],
    List<String>? fixed,
  }) {
    final okf = validation ?? loaded.validate();
    switch (selection) {
      case _ when !okf.isConformant:
        return ProfileValidationResult._(okf, _blocked(selection), [
          ..._reasons(selection),
          ...diagnostics,
        ], fixed: fixed);
      case UnselectedProfile(:final reasons):
        return ProfileValidationResult._(okf, const NotAssessed(), [
          ...reasons,
          ...diagnostics,
        ], fixed: fixed);
      case SelectedProfile():
        return _assess(
          okf,
          loaded,
          selection,
          fixed: fixed,
          diagnostics: diagnostics,
        );
    }
  }

  static List<EngineDiagnostic> _reasons(ProfileSelection selection) =>
      switch (selection) {
        UnselectedProfile(:final reasons) => reasons,
        SelectedProfile(:final notes) => notes,
      };

  Future<ProfileValidationResult> _fixThenAssess(
    OkfSpecValidation validation,
    OkfBundleLoadResult loaded,
    SelectedProfile selection,
  ) async {
    final profile = selection.profile;
    final files = ProfileProjection(
      buildGraph: buildGraph,
    ).generatedFiles(selection, loaded);
    if (files == null) {
      return _assess(
        validation,
        loaded,
        selection,
        diagnostics: [
          EngineDiagnostic(
            DiagnosticCode.fixNotApplied,
            'Profile ${profile.selected.id} ${profile.selected.release} '
            'has no fixable rules.',
          ),
        ],
      );
    }
    final (:written, :failure) = await writeGeneratedFiles(
      loaded.rootPath,
      files,
    );
    if (written.isEmpty) {
      return _assess(
        validation,
        loaded,
        selection,
        fixed: written,
        diagnostics: [?failure],
      );
    }
    final reloaded = await loader.inspect(loaded.rootPath);
    return _validateLoaded(
      reloaded,
      selection,
      fixed: written,
      diagnostics: [?failure],
    );
  }

  static BlockedByOkf _blocked(ProfileSelection selection) =>
      switch (selection) {
        SelectedProfile(:final profile, :final commits) => BlockedByOkf(
          profile: profile,
          commits: commits,
        ),
        UnselectedProfile() => const BlockedByOkf(),
      };

  ProfileValidationResult _assess(
    OkfSpecValidation validation,
    OkfBundleLoadResult loaded,
    SelectedProfile selection, {
    List<String>? fixed,
    List<EngineDiagnostic> diagnostics = const [],
  }) {
    final profile = selection.profile;
    final facts = BundleFacts.project(
      loaded,
      profile: profile,
      buildGraph: buildGraph,
    );
    final results = evaluate(profile, facts);
    final notes = profile.rules.any(
      (rule) => rule.descriptor.severity == RuleSeverity.note,
    );
    return ProfileValidationResult._(
      validation,
      Assessed(
        profile,
        results.findings.toList()..sort(
          (left, right) => OkfReport.compareFindings(
            left.toOkfFinding(),
            right.toOkfFinding(),
          ),
        ),
        notes
            ? (results.summary.toList()..sort(ProfileSummaryEntry.compare))
            : null,
        commits: selection.commits,
      ),
      [
        ...selection.notes,
        for (final type in profile.project.types)
          EngineDiagnostic(
            DiagnosticCode.projectType,
            'Configured project type ${type.name} is available to this bundle.',
            location: selection.config,
          ),
        ...diagnostics,
        ?_linkGraphUnavailable(profile, facts),
      ],
      fixed: fixed,
    );
  }

  /// Only a chain with a link rule lost anything to a failed graph build.
  static EngineDiagnostic? _linkGraphUnavailable(
    EffectiveProfile profile,
    BundleFacts facts,
  ) {
    if (!profile.needsLinks) return null;
    if (facts.links case LinksUnavailable(:final error)) {
      return EngineDiagnostic(
        DiagnosticCode.linkGraphUnavailable,
        'The OKF link graph could not be built ($error); '
        'link rules were not assessed.',
      );
    }
    return null;
  }
}

/// Writes [files] whose text differs, in path order, stopping at the first
/// failure. [written] lists what changed before any failure.
Future<({List<String> written, EngineDiagnostic? failure})> writeGeneratedFiles(
  String rootPath,
  Map<String, String> files,
) async {
  final written = <String>[];
  for (final path in files.keys.toList()..sort()) {
    try {
      if (await _writeIfChanged(rootPath, path, files[path]!)) {
        written.add(path);
      }
    } on FileSystemException catch (error) {
      final cause = error.osError?.message ?? error.message;
      return (
        written: written,
        failure: EngineDiagnostic(
          DiagnosticCode.fixFailed,
          'Could not write $path: $cause.',
          location: BundleLocation(path),
        ),
      );
    }
  }
  return (written: written, failure: null);
}

Future<bool> _writeIfChanged(String rootPath, String path, String text) async {
  var current = rootPath;
  for (final segment in p.posix.split(path)) {
    current = p.join(current, segment);
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
        'refusing to write through the symbolic link '
        '${p.posix.joinAll(p.split(p.relative(current, from: rootPath)))}',
        current,
      );
    }
  }
  final file = File(current);
  if (await file.exists() &&
      withLfLineEndings(await file.readAsString()) == text) {
    return false;
  }
  final suffix = Random.secure().nextInt(1 << 32).toRadixString(16);
  final temporary = File(
    p.join(file.parent.path, '.${p.basename(current)}.wayfinder-$suffix.tmp'),
  );
  try {
    await temporary.create(exclusive: true);
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(current);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
  return true;
}
