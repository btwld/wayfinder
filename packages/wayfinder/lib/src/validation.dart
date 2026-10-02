import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'profile_finding.dart';
import 'profile_release.dart';
import 'profile_rule_descriptors.dart';
import 'rules/builtins.dart';
import 'rules/catalog.dart';
import 'rules/evaluate.dart';
import 'rules/facts.dart';
import 'rules/profile.dart';
import 'rules/registries.dart';
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
  unsupported('UNSUPPORTED'),
  blockedByOkf('BLOCKED BY OKF');

  const ProfileState(this.wireValue);
  final String wireValue;
}

enum AutomatedGateState {
  pass('PASS', OkfExitCode.success),
  fail('FAIL', OkfExitCode.findings),
  unsupported('UNSUPPORTED', OkfExitCode.usage);

  const AutomatedGateState(this.wireValue, this.okfExitCode);
  final String wireValue;

  /// The process outcome under okf's exit-code contract: gate failure exits
  /// through `findings`, and an invocation that could not assess the declared
  /// release exits through `usage`.
  final OkfExitCode okfExitCode;

  int get exitCode => okfExitCode.value;
}

enum ProfileFixState {
  applied('APPLIED'),
  failed('FAILED'),
  notApplied('NOT APPLIED');

  const ProfileFixState(this.wireValue);
  final String wireValue;
}

/// What `validate --fix` did before the assessment it precedes.
final class ProfileFix {
  ProfileFix.written(Iterable<String> paths)
    : state = ProfileFixState.applied,
      written = List<String>.unmodifiable(paths),
      reason = null;

  /// A write failed after [paths] were written; [reason] names the file.
  ProfileFix.failed(Iterable<String> paths, String this.reason)
    : state = ProfileFixState.failed,
      written = List<String>.unmodifiable(paths);

  const ProfileFix.notApplied(String this.reason)
    : state = ProfileFixState.notApplied,
      written = const [];

  final ProfileFixState state;

  /// Bundle-relative paths written, in path order; empty when every fixed
  /// file was already current.
  final List<String> written;

  /// Why the fix failed or could not run.
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.wireValue,
    'written': written,
    'reason': ?reason,
  };

  Iterable<String> toTextLines() sync* {
    for (final path in written) {
      yield 'Fix: wrote $path';
    }
    switch (state) {
      case ProfileFixState.applied when written.isEmpty:
        yield 'Fix: every generated file is current.';
      case ProfileFixState.applied:
        break;
      case ProfileFixState.failed:
        yield 'Fix: failed; $reason.';
      case ProfileFixState.notApplied:
        yield 'Fix: not applied; $reason.';
    }
  }
}

final class ProfileValidationResult {
  ProfileValidationResult._({
    required this.okfValidation,
    required this.profileRelease,
    required this.profileState,
    required Iterable<ProfileFinding> findings,
    required this.automatedGateState,
    this.summary,
    this.fix,
    this.catalogs,
    this.projectConfig,
  }) : findings = List<ProfileFinding>.unmodifiable(findings);

  ProfileValidationResult.blockedByOkf(
    OkfSpecValidation validation, {
    ProfileFix? fix,
  }) : this._(
         okfValidation: validation,
         profileRelease: null,
         profileState: ProfileState.blockedByOkf,
         findings: const <ProfileFinding>[],
         automatedGateState: AutomatedGateState.fail,
         fix: fix,
       );

  ProfileValidationResult.undispatched(
    OkfSpecValidation validation,
    ProfileFinding finding, {
    ProfileFix? fix,
    String? configFile,
  }) : this._(
         okfValidation: validation,
         profileRelease: null,
         profileState: ProfileState.unsupported,
         findings: <ProfileFinding>[finding],
         automatedGateState: AutomatedGateState.unsupported,
         fix: fix,
         projectConfig: configFile == null
             ? null
             : (reported: finding.path, file: configFile),
       );

  ProfileValidationResult.unsupported(
    OkfSpecValidation validation,
    String release, {
    ProfileFix? fix,
  }) : this._(
         okfValidation: validation,
         profileRelease: release,
         profileState: ProfileState.unsupported,
         findings: const <ProfileFinding>[],
         automatedGateState: AutomatedGateState.unsupported,
         fix: fix,
       );

  factory ProfileValidationResult.assessed(
    OkfSpecValidation validation,
    ({List<ProfileFinding> findings, List<ProfileSummaryEntry> summary})
    results,
    List<RuleCatalog> catalogs, {
    ProfileFix? fix,
    ({String reported, String file})? projectConfig,
  }) {
    final stableFindings = List<ProfileFinding>.unmodifiable(
      results.findings.toList()..sort(
        (left, right) => OkfReport.compareFindings(
          left.toOkfFinding(),
          right.toOkfFinding(),
        ),
      ),
    );
    final failed = stableFindings.any(
      (finding) => finding.severity == OkfFindingSeverity.error,
    );
    return ProfileValidationResult._(
      okfValidation: validation,
      profileRelease: catalogs.first.release,
      profileState: failed ? ProfileState.fail : ProfileState.pass,
      findings: stableFindings,
      automatedGateState: failed
          ? AutomatedGateState.fail
          : AutomatedGateState.pass,
      summary:
          catalogs.any(
            (catalog) => catalog.rules.any(
              (rule) => rule.descriptor.severity == RuleSeverity.note,
            ),
          )
          ? List.unmodifiable(
              results.summary.toList()..sort(ProfileSummaryEntry.compare),
            )
          : null,
      fix: fix,
      catalogs: List<RuleCatalog>.unmodifiable(catalogs),
      projectConfig: projectConfig,
    );
  }

  final OkfSpecValidation okfValidation;
  final String? profileRelease;
  final ProfileState profileState;
  final List<ProfileFinding> findings;
  final AutomatedGateState automatedGateState;

  /// What the assessment found that the Profile permits, in canonical order.
  /// Null unless an assessed catalog declares a note rule, so a release
  /// without one keeps its output shape.
  final List<ProfileSummaryEntry>? summary;

  /// Present when the caller asked for `--fix`.
  final ProfileFix? fix;

  /// The catalog chain the bundle was assessed against, base first
  /// ([EffectiveProfile.catalogs]); null when no release was assessed.
  final List<RuleCatalog>? catalogs;

  /// Where findings about the project configuration point. Their
  /// [ProfileFinding.path] is the configured path as given or the file's
  /// basename, which is not bundle-relative; [file] is the file read.
  final ({String reported, String file})? projectConfig;

  OkfReport get okfReport => okfValidation.report;
  OkfState get okfState =>
      okfValidation.isConformant ? OkfState.pass : OkfState.fail;

  /// A failed fix exits as a failed invocation, whatever the assessment of
  /// the partly written bundle found.
  int get exitCode => fix?.state == ProfileFixState.failed
      ? OkfExitCode.usage.value
      : automatedGateState.exitCode;

  Map<String, Object?> toJson() => <String, Object?>{
    if (fix case final fix?) 'fix': fix.toJson(),
    'okf': <String, Object?>{
      'state': okfState.wireValue,
      'report': okfReport.toJson(),
    },
    'profile': <String, Object?>{
      'release': profileRelease,
      'state': profileState.wireValue,
      'findings': findings.map((finding) => finding.toJson()).toList(),
      if (summary case final summary?)
        'summary': summary.map((entry) => entry.toJson()).toList(),
    },
    'judgment_rules': const <String, Object>{'state': 'UNASSESSED'},
    'automated_gate': <String, Object>{'state': automatedGateState.wireValue},
  };

  Iterable<String> toTextLines() sync* {
    if (fix case final fix?) yield* fix.toTextLines();
    yield 'OKF: ${okfState.wireValue}';
    yield* okfReport.toTextLines();
    final errors = _countBySeverity(OkfFindingSeverity.error);
    final advisories = _countBySeverity(OkfFindingSeverity.advisory);
    yield 'OKF Report: $errors error(s), $advisories advisory(ies).';
    final release = profileRelease ?? 'UNDECLARED';
    yield 'Profile $release: ${profileState.wireValue}';
    if (profileState == ProfileState.unsupported && profileRelease != null) {
      yield 'UNSUPPORTED PROFILE RELEASE: $release';
    }
    for (final finding in findings) {
      yield finding.toText();
    }
    if (summary case final summary? when summary.isNotEmpty) {
      yield 'Summary:';
      for (final entry in summary) {
        yield entry.toText();
      }
    }
    yield 'Judgment Rules: UNASSESSED';
    yield 'Automated gate: ${automatedGateState.wireValue}';
  }

  int _countBySeverity(OkfFindingSeverity severity) => okfReport.findings
      .where((finding) => finding.severity == severity)
      .length;
}

/// Source data obtained after the independent OKF check has passed.
final class ProfileSourceResolution {
  const ProfileSourceResolution({this.bindings, this.error});

  final Map<String, WayfinderProfileBinding>? bindings;
  final String? error;
}

final class ProfileValidator {
  const ProfileValidator({this.loader = const OkfBundleLoader()});

  final OkfBundleLoader loader;

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
    if (!validation.isConformant) {
      return ProfileValidationResult.blockedByOkf(
        validation,
        fix: fix ? const ProfileFix.notApplied('OKF failed') : null,
      );
    }
    final unassessed = fix
        ? const ProfileFix.notApplied(
            'no supported Profile release was selected',
          )
        : null;
    final sourceResolution = await resolveSources?.call();
    final resolvedConfig = await _readProjectConfig(
      bundlePath,
      configPath: configPath,
      resolvedProfiles: sourceResolution?.bindings ?? resolvedProfiles,
      resolutionError: sourceResolution?.error ?? resolutionError,
    );
    if (resolvedConfig.finding case final finding?) {
      return ProfileValidationResult.undispatched(
        validation,
        finding,
        fix: unassessed,
        configFile: resolvedConfig.file,
      );
    }
    final EffectiveProfile profile;
    ({String reported, String file})? projectConfig;
    if (resolvedConfig.value case final configured?) {
      final binding = configured.profile;
      if (binding.release != externalProfileRelease ||
          binding.implementsId != builtinProfileId) {
        return ProfileValidationResult.unsupported(
          validation,
          binding.release,
          fix: unassessed,
        );
      }
      final reported = configPath ?? p.basename(configured.configPath);
      profile = _configuredProfile(configured, reportedConfigPath: reported);
      projectConfig = (reported: reported, file: configured.configPath);
    } else {
      final declaration = _readDeclaration(loaded);
      if (declaration.finding case final finding?) {
        return ProfileValidationResult.undispatched(
          validation,
          finding,
          fix: unassessed,
        );
      }
      final values = declaration.values!;
      final release = values['concepta_profile']!;
      if (release != legacyProfileRelease) {
        return ProfileValidationResult.unsupported(
          validation,
          release,
          fix: unassessed,
        );
      }
      final registries = LegacyRegistries(loaded);
      profile = EffectiveProfile(
        [RuleCatalog.installed(builtinProfileId, release)],
        legacyRegistryVocabulary(registries),
        legacy: (declaration: values, registries: registries),
      );
    }
    if (!fix) {
      return _assess(validation, loaded, profile, projectConfig: projectConfig);
    }
    return _fixThenAssess(validation, loaded, profile, projectConfig);
  }

  Future<ProfileValidationResult> _fixThenAssess(
    OkfSpecValidation validation,
    OkfBundleLoadResult loaded,
    EffectiveProfile profile,
    ({String reported, String file})? projectConfig,
  ) async {
    final files = fixes(profile, BundleFacts.project(loaded, profile: profile));
    if (files == null) {
      return _assess(
        validation,
        loaded,
        profile,
        projectConfig: projectConfig,
        fix: ProfileFix.notApplied(
          'Profile ${profile.base.release} has no fixable rules',
        ),
      );
    }
    final fix = await writeGeneratedFiles(loaded.rootPath, files);
    if (fix.written.isEmpty) {
      return _assess(
        validation,
        loaded,
        profile,
        fix: fix,
        projectConfig: projectConfig,
      );
    }
    final reloaded = await loader.inspect(loaded.rootPath);
    final revalidation = reloaded.validate();
    if (!revalidation.isConformant) {
      return ProfileValidationResult.blockedByOkf(revalidation, fix: fix);
    }
    return _assess(
      revalidation,
      reloaded,
      profile,
      fix: fix,
      projectConfig: projectConfig,
    );
  }
}

/// Writes each of [files] whose bytes differ beneath [rootPath], in path
/// order, stopping at the first failure. Each file is written to a temporary
/// sibling and renamed into place, so a reader sees the old bytes or the new,
/// never part of either. A symbolic link at any segment below [rootPath] is
/// refused, so a write cannot leave the bundle.
Future<ProfileFix> writeGeneratedFiles(
  String rootPath,
  Map<String, String> files,
) async {
  final written = <String>[];
  for (final path in files.keys.toList()..sort()) {
    try {
      if (await _writeIfChanged(rootPath, path, utf8.encode(files[path]!))) {
        written.add(path);
      }
    } on FileSystemException catch (error) {
      final cause = error.osError?.message ?? error.message;
      return ProfileFix.failed(written, 'could not write $path: $cause');
    }
  }
  return ProfileFix.written(written);
}

Future<bool> _writeIfChanged(
  String rootPath,
  String path,
  List<int> bytes,
) async {
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
      const ListEquality<int>().equals(await file.readAsBytes(), bytes)) {
    return false;
  }
  final suffix = Random.secure().nextInt(1 << 32).toRadixString(16);
  final temporary = File(
    p.join(file.parent.path, '.${p.basename(current)}.wayfinder-$suffix.tmp'),
  );
  try {
    await temporary.create(exclusive: true);
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(current);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
  return true;
}

EffectiveProfile _configuredProfile(
  WayfinderResolvedConfig configured, {
  required String reportedConfigPath,
}) {
  final binding = configured.profile;
  return EffectiveProfile(
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
    configPath: reportedConfigPath,
  );
}

ProfileValidationResult _assess(
  OkfSpecValidation validation,
  OkfBundleLoadResult loaded,
  EffectiveProfile profile, {
  ProfileFix? fix,
  ({String reported, String file})? projectConfig,
}) {
  final facts = BundleFacts.project(loaded, profile: profile);
  return ProfileValidationResult.assessed(
    validation,
    evaluate(profile, facts),
    profile.catalogs,
    fix: fix,
    projectConfig: projectConfig,
  );
}

Future<_ConfigRead> _readProjectConfig(
  String bundlePath, {
  String? configPath,
  Map<String, WayfinderProfileBinding>? resolvedProfiles,
  String? resolutionError,
}) async {
  final file = configPath == null
      ? await _findProjectConfig(bundlePath)
      : File(configPath);
  if (file == null || !await file.exists()) {
    if (configPath != null) {
      return _ConfigRead.finding(
        ProfileFinding(
          descriptor: DispatchRule.configurationReadable,
          message: 'Configuration file $configPath does not exist.',
          path: configPath,
        ),
        configPath,
      );
    }
    return const _ConfigRead.none();
  }
  WayfinderProjectConfig config;
  try {
    config = await WayfinderProjectConfig.read(file);
  } on WayfinderConfigException catch (error) {
    // An unselected ancestor file cannot silently migrate a 2026.2 bundle.
    if (configPath == null &&
        await File(p.join(bundlePath, 'profile.md')).exists()) {
      return const _ConfigRead.none();
    }
    return _ConfigRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.configurationReadable,
        message: error.message,
        path: configPath ?? p.basename(file.path),
        profileRelease: externalProfileRelease,
      ),
      file.path,
    );
  }
  try {
    final projectRoot = await file.parent.resolveSymbolicLinks();
    final requested = await Directory(bundlePath).resolveSymbolicLinks();
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
      return const _ConfigRead.none();
    }
    if (unreadablePaths.isNotEmpty) {
      throw WayfinderConfigException(
        'Configured bundle ${unreadablePaths.first} does not exist or is unreadable.',
      );
    }
    for (final entry in realPaths.entries) {
      if (!p.isWithin(projectRoot, entry.value)) {
        throw WayfinderConfigException(
          'Bundle ${entry.key} resolves outside the project.',
        );
      }
      for (final other in realPaths.entries) {
        if (entry.key != other.key &&
            (p.equals(entry.value, other.value) ||
                p.isWithin(entry.value, other.value) ||
                p.isWithin(other.value, entry.value))) {
          throw WayfinderConfigException(
            'Configured bundles overlap after resolving symlinks.',
          );
        }
      }
    }
    if (configPath == null && selectedPath == null) {
      throw WayfinderConfigException(
        'Bundle $bundlePath is not listed in ${p.basename(file.path)}.',
      );
    }
    final selected = config.resolve(
      bundlePath: selectedPath ?? bundlePath,
      configPath: file.absolute.path,
      resolvedProfiles: resolvedProfiles,
    );
    final declared = config.profiles[selected.bundle.profile]!;
    if (declared.source != null) {
      final effective = resolvedProfiles?[declared.id];
      if (effective == null ||
          effective.id != declared.id ||
          effective.source?.git != declared.source!.git ||
          effective.source?.ref != declared.source!.ref ||
          effective.source?.path != declared.source!.path) {
        throw WayfinderConfigException(
          resolutionError ??
              'Direct Profile source is unresolved. Run wayfinder get.',
        );
      }
    }
    return _ConfigRead.value(selected);
  } on WayfinderConfigException catch (error) {
    return _ConfigRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.configurationReadable,
        message: error.message,
        path: configPath ?? p.basename(file.path),
        profileRelease: externalProfileRelease,
      ),
      file.path,
    );
  } on FileSystemException catch (error) {
    return _ConfigRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.configurationBundleBinding,
        message: 'Configured bundle path is not readable: ${error.message}.',
        path: configPath ?? p.basename(file.path),
        profileRelease: externalProfileRelease,
      ),
      file.path,
    );
  }
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

final class _ConfigRead {
  const _ConfigRead.none() : value = null, finding = null, file = null;
  const _ConfigRead.value(this.value) : finding = null, file = null;
  const _ConfigRead.finding(this.finding, this.file) : value = null;

  final WayfinderResolvedConfig? value;
  final ProfileFinding? finding;

  final String? file;
}

_DeclarationRead _readDeclaration(OkfBundleLoadResult loaded) {
  final document = loaded.documents['profile.md'];
  if (document == null) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.profileDeclarationPresent,
        message: 'The bundle must contain profile.md.',
        path: 'profile.md',
      ),
    );
  }
  final yamlSource = _firstYamlFence(document.body);
  if (yamlSource == null) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.profileDeclarationReadable,
        message: 'profile.md must contain a fenced yaml declaration.',
        path: 'profile.md',
      ),
    );
  }
  Object? parsed;
  try {
    parsed = loadYaml(yamlSource);
  } on YamlException {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.profileDeclarationReadable,
        message: 'The first fenced yaml declaration in profile.md is invalid.',
        path: 'profile.md',
      ),
    );
  }
  if (parsed is! Map) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: DispatchRule.profileDeclarationFields,
        message: 'The Profile declaration must be a YAML mapping.',
        path: 'profile.md',
      ),
    );
  }
  final values = <String, String>{};
  for (final key in const <String>['concepta_profile', 'okf_version']) {
    final value = parsed[key];
    if (value is! String || value.trim().isEmpty) {
      return const _DeclarationRead.finding(
        ProfileFinding(
          descriptor: DispatchRule.profileDeclarationFields,
          message:
              'The Profile declaration must contain non-empty string '
              'values for concepta_profile and okf_version.',
          path: 'profile.md',
        ),
      );
    }
    values[key] = value;
  }
  return _DeclarationRead.values(values);
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

final class _DeclarationRead {
  const _DeclarationRead.values(this.values) : finding = null;
  const _DeclarationRead.finding(this.finding) : values = null;

  final Map<String, String>? values;
  final ProfileFinding? finding;
}
