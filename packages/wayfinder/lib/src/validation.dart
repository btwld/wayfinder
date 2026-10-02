import 'dart:io';
import 'dart:math';

import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'diagnostics.dart';
import 'profile_finding.dart';
import 'profile_release.dart';
import 'profile_rule_descriptors.dart';
import 'rules/builtins.dart';
import 'rules/catalog.dart';
import 'rules/evaluate.dart';
import 'rules/facts.dart';
import 'rules/profile.dart';
import 'rules/registries.dart';
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

/// Every rule of [catalogs] ran against the bundle.
final class Assessed extends ProfileAssessment {
  Assessed(
    Iterable<RuleCatalog> catalogs,
    Iterable<ProfileFinding> findings,
    Iterable<ProfileSummaryEntry>? summary,
  ) : catalogs = List.unmodifiable(catalogs),
      findings = List.unmodifiable(findings),
      summary = summary == null ? null : List.unmodifiable(summary);

  /// The catalog chain, base first ([EffectiveProfile.catalogs]).
  final List<RuleCatalog> catalogs;

  /// In canonical okf order.
  final List<ProfileFinding> findings;

  /// What the assessment found that the Profile permits, in canonical order.
  /// Null unless an assessed catalog declares a note rule, so a release
  /// without one keeps its output shape.
  final List<ProfileSummaryEntry>? summary;

  String get release => catalogs.first.release;
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

  List<RuleCatalog> get catalogs => switch (profile) {
    Assessed(:final catalogs) => catalogs,
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

/// Source data obtained after the independent OKF check has passed.
final class ProfileSourceResolution {
  const ProfileSourceResolution({this.bindings, this.error});

  final Map<String, WayfinderProfileBinding>? bindings;
  final String? error;
}

/// Which Profile a run assesses, or why there is none.
sealed class _Selection {
  const _Selection();
}

final class _Selected extends _Selection {
  const _Selected(this.profile, {this.config});

  final EffectiveProfile profile;

  /// The project file that selected [profile]; null for a 2026.2
  /// `profile.md` declaration.
  final ProjectFileLocation? config;
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
    Map<String, WayfinderProfileBinding>? resolvedProfiles,
    String? resolutionError,
    Future<ProfileSourceResolution> Function()? resolveSources,
    bool fix = false,
  }) async {
    final loaded = await loader.inspect(bundlePath);
    final validation = loaded.validate();
    final sourceResolution = await resolveSources?.call();
    final selection =
        await _configuredSelection(
          bundlePath,
          configPath: configPath,
          resolvedProfiles: sourceResolution?.bindings ?? resolvedProfiles,
          resolutionError: sourceResolution?.error ?? resolutionError,
        ) ??
        _declaredSelection(loaded);
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
    ProjectFileLocation? config,
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
            'Profile ${profile.base.release} has no fixable rules.',
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
    ProjectFileLocation? config, {
    List<String>? fixed,
    List<EngineDiagnostic> diagnostics = const [],
  }) {
    final facts = BundleFacts.project(
      loaded,
      profile: profile,
      buildGraph: buildGraph,
    );
    final results = evaluate(profile, facts);
    final notes = profile.catalogs.any(
      (catalog) => catalog.rules.any(
        (rule) => rule.descriptor.severity == RuleSeverity.note,
      ),
    );
    return ProfileValidationResult._(
      validation,
      Assessed(
        profile.catalogs,
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
        if (config != null)
          for (final name in profile.vocabulary.projectTypes)
            EngineDiagnostic(
              DiagnosticCode.projectType,
              'Configured project type $name is available to this bundle.',
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

/// The Profile a `wayfinder.json` selects for [bundlePath]; null when no
/// project file applies, so a 2026.2 `profile.md` declaration decides.
Future<_Selection?> _configuredSelection(
  String bundlePath, {
  String? configPath,
  Map<String, WayfinderProfileBinding>? resolvedProfiles,
  String? resolutionError,
}) async {
  final file = configPath == null
      ? await _findProjectConfig(bundlePath)
      : File(configPath);
  if (file == null || !await file.exists()) {
    if (configPath == null) return null;
    return _Unselected(
      EngineDiagnostic(
        DiagnosticCode.configMissing,
        'Configuration file $configPath does not exist.',
        location: ProjectFileLocation(path: configPath, file: configPath),
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
    // An unselected ancestor file cannot silently migrate a 2026.2 bundle.
    if (configPath == null &&
        await File(p.join(bundlePath, 'profile.md')).exists()) {
      return null;
    }
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
  if (configPath == null &&
      selectedPath == null &&
      await File(p.join(bundlePath, 'profile.md')).exists()) {
    // An unrelated project configuration cannot migrate a 2026.2 bundle.
    return null;
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
      resolvedProfiles: resolvedProfiles,
    );
  } on WayfinderConfigException catch (error) {
    return unselected(DiagnosticCode.bundleUnbound, error.message);
  }
  final declared = config.profiles[selected.bundle.profile]!;
  if (declared.source != null) {
    final effective = resolvedProfiles?[declared.id];
    if (effective == null ||
        effective.id != declared.id ||
        effective.source?.git != declared.source!.git ||
        effective.source?.ref != declared.source!.ref ||
        effective.source?.path != declared.source!.path) {
      return unselected(
        DiagnosticCode.profileUnresolved,
        resolutionError ??
            'Direct Profile source is unresolved. Run wayfinder get.',
      );
    }
  }
  final binding = selected.profile;
  if (binding.release != externalProfileRelease ||
      binding.implementsId != builtinProfileId) {
    return unselected(
      DiagnosticCode.profileUnsupported,
      'Profile ${binding.implementsId} ${binding.release} is not supported; '
      'this wayfinder assesses $builtinProfileId $externalProfileRelease.',
    );
  }
  return _Selected(
    EffectiveProfile(
      [
        RuleCatalog.installed(binding.implementsId, binding.release),
        ...binding.catalogs,
      ],
      Vocabulary(
        standardTypes: externalStandardTypes.map((row) => row.$1).toList(),
        projectTypes: binding.types.map((type) => type.name).toList(),
        types: binding.typeNames.toList(),
        tags: binding.tagNames.toList(),
        relationships: binding.relationshipNames.toList(),
        actors: binding.actors.keys.toList(),
      ),
    ),
    config: location,
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

/// The Profile a 2026.2 `profile.md` declaration selects.
_Selection _declaredSelection(OkfBundleLoadResult loaded) {
  const location = BundleLocation('profile.md');
  _Unselected invalid(String message) => _Unselected(
    EngineDiagnostic(DiagnosticCode.configInvalid, message, location: location),
  );

  final document = loaded.documents['profile.md'];
  if (document == null && loaded.paths.contains('profile.md')) {
    return invalid('profile.md is not a readable OKF document.');
  }
  if (document == null) {
    return const _Unselected(
      EngineDiagnostic(
        DiagnosticCode.configMissing,
        'No wayfinder.json lists the bundle, and it has no profile.md '
        'declaration.',
      ),
    );
  }
  final yamlSource = _firstYamlFence(document.body);
  if (yamlSource == null) {
    return invalid('profile.md must contain a fenced yaml declaration.');
  }
  Object? parsed;
  try {
    parsed = loadYaml(yamlSource);
  } on YamlException {
    return invalid(
      'The first fenced yaml declaration in profile.md is invalid.',
    );
  }
  if (parsed is! Map) {
    return invalid('The Profile declaration must be a YAML mapping.');
  }
  final values = <String, String>{};
  for (final key in const <String>['concepta_profile', 'okf_version']) {
    final value = parsed[key];
    if (value is! String || value.trim().isEmpty) {
      return invalid(
        'The Profile declaration must contain non-empty string '
        'values for concepta_profile and okf_version.',
      );
    }
    values[key] = value;
  }
  final release = values['concepta_profile']!;
  if (release != legacyProfileRelease) {
    return _Unselected(
      EngineDiagnostic(
        DiagnosticCode.profileUnsupported,
        'Profile release $release is not supported; this wayfinder assesses '
        '$legacyProfileRelease declarations.',
        location: location,
      ),
    );
  }
  final registries = LegacyRegistries(loaded);
  return _Selected(
    EffectiveProfile(
      [RuleCatalog.installed(builtinProfileId, release)],
      legacyRegistryVocabulary(registries),
      legacyDispatch: (declaration: values, registries: registries),
    ),
  );
}

String? _firstYamlFence(String body) {
  final nodes = markdown.Document(encodeHtml: false).parse(body);
  String? find(Iterable<markdown.Node> candidates) {
    for (final node in candidates) {
      if (node case final markdown.Element element) {
        final children = element.children;
        if (element.tag == 'pre' && children != null && children.isNotEmpty) {
          final code = children.first;
          if (code is markdown.Element &&
              code.tag == 'code' &&
              code.attributes['class'] == 'language-yaml') {
            return code.textContent;
          }
        }
        if (children != null) {
          final nested = find(children);
          if (nested != null) return nested;
        }
      }
    }
    return null;
  }

  return find(nodes);
}
