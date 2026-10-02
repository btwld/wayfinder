import 'dart:io';
import 'dart:math';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import 'diagnostics.dart';
import 'generated/published_schemas.g.dart';
import 'profile_finding.dart';
import 'profile_package.dart';
import 'profile_rule_descriptors.dart';
import 'rules/evaluate.dart';
import 'rules/facts.dart';
import 'rules/profile.dart';
import 'rules/structure_builtins.dart' show withLfLineEndings;
import 'wayfinder_config.dart';

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

/// What the Profile layer of a run did.
sealed class ProfileAssessment {
  const ProfileAssessment();
}

/// Every rule of [profile] ran against the bundle.
final class Assessed extends ProfileAssessment {
  Assessed(
    this.profile,
    Iterable<ProfileFinding> findings,
    Iterable<ProfileSummaryEntry>? summary,
  ) : findings = List.unmodifiable(findings),
      summary = summary == null ? null : List.unmodifiable(summary);

  final EffectiveProfile profile;

  /// In canonical okf order.
  final List<ProfileFinding> findings;

  /// What the assessment found that the Profile permits, in canonical order.
  /// Null unless an assessed package declares a note rule, so a Profile
  /// without one keeps its output shape.
  final List<ProfileSummaryEntry>? summary;

  String get release => profile.selected.release;
}

/// OKF failed, so no Profile rule ran.
final class BlockedByOkf extends ProfileAssessment {
  const BlockedByOkf();
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

  String? get profileRelease => switch (profile) {
    Assessed(:final release) => release,
    _ => null,
  };

  List<ProfileFinding> get findings => switch (profile) {
    Assessed(:final findings) => findings,
    _ => const [],
  };

  List<ProfileSummaryEntry>? get summary => switch (profile) {
    Assessed(:final summary) => summary,
    _ => null,
  };

  /// The assessed packages, root ancestor first; empty when none ran.
  List<ProfilePackage> get chain => switch (profile) {
    Assessed(:final profile) => profile.chain,
    _ => const [],
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'okf': <String, Object?>{
      'state': okfState.wireValue,
      'report': okfReport.toJson(),
    },
    'profile': <String, Object?>{
      'release': ?profileRelease,
      'state': profileState.wireValue,
      'findings': findings.map((finding) => finding.toJson()).toList(),
      if (summary case final summary?)
        'summary': summary.map((entry) => entry.toJson()).toList(),
    },
    'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
    if (fixed case final fixed?) 'fix': <String, Object?>{'written': fixed},
    'gate': <String, Object>{'state': gate.wireValue},
    'engine': <String, Object>{'okf': okfPackageVersion},
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
    yield switch (profileRelease) {
      final release? => 'Profile $release: ${profileState.wireValue}',
      null => 'Profile: ${profileState.wireValue}',
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

/// What the resolver could compose from the lock and the local cache,
/// without fetching: the effective Profile per configured id, or why it
/// stopped. A missing id is reported as [failure], or as unresolved when
/// there is none.
final class ProfileSourceResolution {
  const ProfileSourceResolution({this.profiles, this.failure});

  final Map<ProfileId, EffectiveProfile>? profiles;
  final ({DiagnosticCode code, String message})? failure;
}

/// The failure validation reports when the chain of [id] does not compose.
/// `get` stops with the same text, so both paths read one format.
({DiagnosticCode code, String message}) compositionFailure(
  ProfileId id,
  ProfileCompositionException error,
) => (
  code: DiagnosticCode.profileComposition,
  message: 'Profile $id: ${error.message}',
);

/// Which Profile a run assesses, or why there is none.
sealed class _Selection {
  const _Selection();
}

final class _Selected extends _Selection {
  const _Selected(this.profile, {required this.config});

  final EffectiveProfile profile;

  /// The project file that selected [profile].
  final ProjectFileLocation config;
}

final class _Unselected extends _Selection {
  const _Unselected(this.reason);

  final EngineDiagnostic reason;
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

  /// Never throws for bundle or configuration content: what cannot be
  /// assessed is reported as a diagnostic.
  Future<ProfileValidationResult> validate(
    String bundlePath, {
    String? configPath,
    ProfileSourceResolution resolution = const ProfileSourceResolution(),
    bool fix = false,
  }) async {
    final loaded = await loader.inspect(bundlePath);
    final validation = loaded.validate();
    final selection = await _configuredSelection(
      bundlePath,
      configPath: configPath,
      resolution: resolution,
    );
    final reasons = [if (selection case _Unselected(:final reason)) reason];
    if (!validation.isConformant) {
      return ProfileValidationResult._(validation, const BlockedByOkf(), [
        ...reasons,
        if (fix)
          const EngineDiagnostic(DiagnosticCode.fixNotApplied, 'OKF failed.'),
      ]);
    }
    switch (selection) {
      case _Unselected():
        return ProfileValidationResult._(validation, const NotAssessed(), [
          ...reasons,
          if (fix)
            const EngineDiagnostic(
              DiagnosticCode.fixNotApplied,
              'No supported Profile release was selected.',
            ),
        ]);
      case _Selected(:final profile, :final config):
        if (!fix) return _assess(validation, loaded, profile, config);
        return _fixThenAssess(validation, loaded, profile, config);
    }
  }

  Future<ProfileValidationResult> _fixThenAssess(
    OkfSpecValidation validation,
    OkfBundleLoadResult loaded,
    EffectiveProfile profile,
    ProjectFileLocation config,
  ) async {
    final files = fixes(
      profile,
      BundleFacts.project(loaded, profile: profile, buildGraph: buildGraph),
    );
    if (files == null) {
      return _assess(
        validation,
        loaded,
        profile,
        config,
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
        profile,
        config,
        fixed: written,
        diagnostics: [?failure],
      );
    }
    final reloaded = await loader.inspect(loaded.rootPath);
    final revalidation = reloaded.validate();
    if (!revalidation.isConformant) {
      return ProfileValidationResult._(revalidation, const BlockedByOkf(), [
        ?failure,
      ], fixed: written);
    }
    return _assess(
      revalidation,
      reloaded,
      profile,
      config,
      fixed: written,
      diagnostics: [?failure],
    );
  }

  ProfileValidationResult _assess(
    OkfSpecValidation validation,
    OkfBundleLoadResult loaded,
    EffectiveProfile profile,
    ProjectFileLocation config, {
    List<String>? fixed,
    List<EngineDiagnostic> diagnostics = const [],
  }) {
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
      ),
      [
        for (final type in profile.project.types)
          EngineDiagnostic(
            DiagnosticCode.projectType,
            'Configured project type ${type.name} is available to this bundle.',
            location: config,
          ),
        ...diagnostics,
        if (facts.links case LinksUnavailable(:final error))
          EngineDiagnostic(
            DiagnosticCode.linkGraphUnavailable,
            'The OKF link graph could not be built ($error); '
            'link rules were not assessed.',
          ),
      ],
      fixed: fixed,
    );
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

/// The Profile the `wayfinder.json` that lists [bundlePath] selects. Without
/// [configPath], the nearest file above the bundle applies.
Future<_Selection> _configuredSelection(
  String bundlePath, {
  required String? configPath,
  required ProfileSourceResolution resolution,
}) async {
  final File file;
  if (configPath != null) {
    file = File(configPath);
    if (!await file.exists()) {
      return _Unselected(
        EngineDiagnostic(
          DiagnosticCode.configMissing,
          'Configuration file $configPath does not exist.',
          location: ProjectFileLocation(path: configPath, file: configPath),
        ),
      );
    }
  } else if (await _findProjectConfig(bundlePath) case final found?) {
    file = found;
  } else {
    return const _Unselected(
      EngineDiagnostic(
        DiagnosticCode.configMissing,
        'No wayfinder.json was found above the bundle.',
      ),
    );
  }
  final location = ProjectFileLocation(
    path: configPath ?? p.basename(file.path),
    file: file.path,
  );
  _Unselected unselected(DiagnosticCode code, String message) =>
      _Unselected(EngineDiagnostic(code, message, location: location));

  WayfinderProjectConfig config;
  try {
    config = await WayfinderProjectConfig.read(file);
  } on WayfinderConfigException catch (error) {
    return unselected(DiagnosticCode.configInvalid, error.message);
  }
  final String projectRoot;
  final String requested;
  try {
    projectRoot = await file.parent.resolveSymbolicLinks();
    requested = await Directory(bundlePath).resolveSymbolicLinks();
  } on FileSystemException catch (error) {
    return unselected(
      DiagnosticCode.bundleUnbound,
      'Configured bundle path is not readable: ${error.message}.',
    );
  }
  String? selectedPath;
  final realPaths = <String, String>{};
  final unreadablePaths = <String>[];
  for (final bundle in config.bundles) {
    final configuredPath = p.normalize(p.join(projectRoot, bundle.path));
    try {
      final realPath = await Directory(configuredPath).resolveSymbolicLinks();
      realPaths[configuredPath] = realPath;
      if (p.equals(realPath, requested)) {
        // Keep the spelling relative to the configuration file for resolve().
        selectedPath = p.normalize(
          p.join(file.absolute.parent.path, bundle.path),
        );
      }
    } on FileSystemException {
      unreadablePaths.add(bundle.path);
    }
  }
  if (unreadablePaths.isNotEmpty) {
    return unselected(
      DiagnosticCode.configInvalid,
      'Configured bundle ${unreadablePaths.first} does not exist or is unreadable.',
    );
  }
  for (final entry in realPaths.entries) {
    if (!p.isWithin(projectRoot, entry.value)) {
      return unselected(
        DiagnosticCode.configInvalid,
        'Bundle ${entry.key} resolves outside the project.',
      );
    }
    for (final other in realPaths.entries) {
      if (entry.key != other.key &&
          (p.equals(entry.value, other.value) ||
              p.isWithin(entry.value, other.value) ||
              p.isWithin(other.value, entry.value))) {
        return unselected(
          DiagnosticCode.configInvalid,
          'Configured bundles overlap after resolving symlinks.',
        );
      }
    }
  }
  final WayfinderResolvedConfig selected;
  try {
    selected = config.resolve(
      bundlePath: selectedPath ?? bundlePath,
      configPath: file.absolute.path,
    );
  } on WayfinderConfigException catch (error) {
    return unselected(DiagnosticCode.bundleUnbound, error.message);
  }
  final id = selected.profile.id;
  if (resolution.profiles?[id] case final effective?) {
    return _Selected(effective, config: location);
  }
  final failure = resolution.failure;
  return unselected(
    failure?.code ?? DiagnosticCode.profileUnresolved,
    failure?.message ?? 'Profile $id is unresolved. Run wayfinder get.',
  );
}

Future<File?> _findProjectConfig(String bundlePath) async {
  var directory = p.dirname(File(bundlePath).absolute.path);
  while (true) {
    final file = File(p.join(directory, 'wayfinder.json'));
    if (await file.exists()) return file;
    final parent = p.dirname(directory);
    if (parent == directory) return null;
    directory = parent;
  }
}
