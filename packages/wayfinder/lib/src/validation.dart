import 'dart:io';

import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'concept_rules.dart';
import 'profile_context.dart';
import 'profile_finding.dart';
import 'profile_release.dart';
import 'profile_rule_descriptors.dart' as rules;
import 'structure_rules.dart';
import 'wayfinder_config.dart';

const supportedOkfRelease = '0.2';

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

final class ProfileValidationResult {
  ProfileValidationResult._({
    required this.okfValidation,
    required this.profileRelease,
    required this.profileState,
    required Iterable<ProfileFinding> findings,
    required this.automatedGateState,
  }) : findings = List<ProfileFinding>.unmodifiable(findings);

  ProfileValidationResult.blockedByOkf(OkfSpecValidation validation)
    : this._(
        okfValidation: validation,
        profileRelease: null,
        profileState: ProfileState.blockedByOkf,
        findings: const <ProfileFinding>[],
        automatedGateState: AutomatedGateState.fail,
      );

  ProfileValidationResult.undispatched(
    OkfSpecValidation validation,
    ProfileFinding finding,
  ) : this._(
        okfValidation: validation,
        profileRelease: null,
        profileState: ProfileState.unsupported,
        findings: <ProfileFinding>[finding],
        automatedGateState: AutomatedGateState.unsupported,
      );

  ProfileValidationResult.unsupported(
    OkfSpecValidation validation,
    String release,
  ) : this._(
        okfValidation: validation,
        profileRelease: release,
        profileState: ProfileState.unsupported,
        findings: const <ProfileFinding>[],
        automatedGateState: AutomatedGateState.unsupported,
      );

  factory ProfileValidationResult.assessed(
    OkfSpecValidation validation,
    Iterable<ProfileFinding> findings,
    String release,
  ) {
    final released = findings.map((finding) => finding.atRelease(release));
    final stableFindings = List<ProfileFinding>.unmodifiable(
      released.toList()..sort(
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
      profileRelease: release,
      profileState: failed ? ProfileState.fail : ProfileState.pass,
      findings: stableFindings,
      automatedGateState: failed
          ? AutomatedGateState.fail
          : AutomatedGateState.pass,
    );
  }

  final OkfSpecValidation okfValidation;
  final String? profileRelease;
  final ProfileState profileState;
  final List<ProfileFinding> findings;
  final AutomatedGateState automatedGateState;

  OkfReport get okfReport => okfValidation.report;
  OkfState get okfState =>
      okfValidation.isConformant ? OkfState.pass : OkfState.fail;
  int get exitCode => automatedGateState.exitCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'okf': <String, Object?>{
      'state': okfState.wireValue,
      'report': okfReport.toJson(),
    },
    'profile': <String, Object?>{
      'release': profileRelease,
      'state': profileState.wireValue,
      'findings': findings.map((finding) => finding.toJson()).toList(),
    },
    'judgment_rules': const <String, Object>{'state': 'UNASSESSED'},
    'automated_gate': <String, Object>{'state': automatedGateState.wireValue},
  };

  Iterable<String> toTextLines() sync* {
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
    yield 'Judgment Rules: UNASSESSED';
    yield 'Automated gate: ${automatedGateState.wireValue}';
  }

  int _countBySeverity(OkfFindingSeverity severity) => okfReport.findings
      .where((finding) => finding.severity == severity)
      .length;
}

final class ProfileValidator {
  const ProfileValidator({this.loader = const OkfBundleLoader()});

  final OkfBundleLoader loader;

  Future<ProfileValidationResult> validate(
    String bundlePath, {
    String? configPath,
    Map<String, WayfinderProfileBinding>? resolvedProfiles,
  }) async {
    final resolvedConfig = await _readProjectConfig(
      bundlePath,
      configPath: configPath,
      resolvedProfiles: resolvedProfiles,
    );
    final loaded = await loader.inspect(bundlePath);
    final validation = loaded.validate();
    if (!validation.isConformant) {
      return ProfileValidationResult.blockedByOkf(validation);
    }
    if (resolvedConfig.finding case final finding?) {
      return ProfileValidationResult.undispatched(validation, finding);
    }
    if (resolvedConfig.value case final configured?) {
      return _validateConfigured(validation, loaded, configured);
    }
    final declaration = _readDeclaration(loaded);
    if (declaration.finding case final finding?) {
      return ProfileValidationResult.undispatched(validation, finding);
    }
    final values = declaration.values!;
    final release = values['concepta_profile']!;
    if (release != legacyProfileRelease) {
      return ProfileValidationResult.unsupported(validation, release);
    }
    final context = ProfileValidationContext.legacy(release);
    return ProfileValidationResult.assessed(validation, <ProfileFinding>[
      ?_validateOkfBinding(values, loaded, release),
      ...validateConceptRules(loaded, context: context),
      ...validateStructureRules(loaded, context: context),
    ], release);
  }
}

ProfileValidationResult _validateConfigured(
  OkfSpecValidation validation,
  OkfBundleLoadResult loaded,
  WayfinderResolvedConfig configured,
) {
  final context = ProfileValidationContext.external(configured.profile);
  if (configured.profile.release != externalProfileRelease) {
    return ProfileValidationResult.unsupported(
      validation,
      configured.profile.release,
    );
  }
  return ProfileValidationResult.assessed(validation, <ProfileFinding>[
    ...validateConceptRules(loaded, context: context),
    ...validateStructureRules(loaded, context: context),
  ], configured.profile.release);
}

Future<_ConfigRead> _readProjectConfig(
  String bundlePath, {
  String? configPath,
  Map<String, WayfinderProfileBinding>? resolvedProfiles,
}) async {
  final file = configPath == null
      ? await _findProjectConfig(bundlePath)
      : File(configPath);
  if (file == null || !await file.exists()) {
    if (configPath != null) {
      return _ConfigRead.finding(
        ProfileFinding(
          descriptor: rules.configurationReadable,
          message: 'Configuration file $configPath does not exist.',
          path: p.basename(configPath),
        ),
      );
    }
    return const _ConfigRead.none();
  }
  try {
    final config = await WayfinderProjectConfig.read(file);
    final projectRoot = await file.parent.resolveSymbolicLinks();
    final requested = await Directory(bundlePath).resolveSymbolicLinks();
    String? selectedPath;
    final realPaths = <String>{};
    for (final bundle in config.bundles) {
      final configuredPath = p.normalize(p.join(projectRoot, bundle.path));
      final realPath = await Directory(configuredPath).resolveSymbolicLinks();
      if (!p.isWithin(projectRoot, realPath)) {
        throw WayfinderConfigException(
          'Bundle ${bundle.id} resolves outside the project.',
        );
      }
      if (!realPaths.add(realPath)) {
        throw WayfinderConfigException(
          'Configured bundles resolve to the same directory.',
        );
      }
      if (p.equals(realPath, requested)) selectedPath = configuredPath;
    }
    for (final path in realPaths) {
      if (realPaths.any((other) => other != path && p.isWithin(other, path))) {
        throw WayfinderConfigException(
          'Configured bundles must not be nested.',
        );
      }
    }
    if (configPath == null && selectedPath == null) {
      if (await File(p.join(bundlePath, 'profile.md')).exists()) {
        return const _ConfigRead.none();
      }
      throw WayfinderConfigException(
        'Bundle $bundlePath is not listed in ${p.basename(file.path)}.',
      );
    }
    final selected = config.resolve(
      bundlePath: selectedPath ?? bundlePath,
      configPath: p.join(projectRoot, p.basename(file.path)),
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
        throw const WayfinderConfigException(
          'Direct Profile sources must be resolved before validation.',
        );
      }
    }
    return _ConfigRead.value(selected);
  } on WayfinderConfigException catch (error) {
    return _ConfigRead.finding(
      ProfileFinding(
        descriptor: rules.configurationReadable,
        message: error.message,
        path: p.basename(file.path),
        profileRelease: externalProfileRelease,
      ),
    );
  } on FileSystemException catch (error) {
    return _ConfigRead.finding(
      ProfileFinding(
        descriptor: rules.configurationBundleBinding,
        message: 'Configured bundle path is not readable: ${error.message}.',
        path: p.basename(file.path),
        profileRelease: externalProfileRelease,
      ),
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
  const _ConfigRead.none() : value = null, finding = null;
  const _ConfigRead.value(this.value) : finding = null;
  const _ConfigRead.finding(this.finding) : value = null;

  final WayfinderResolvedConfig? value;
  final ProfileFinding? finding;
}

_DeclarationRead _readDeclaration(OkfBundleLoadResult loaded) {
  final document = loaded.documents['profile.md'];
  if (document == null) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: rules.profileDeclarationPresent,
        message: 'The bundle must contain profile.md.',
        path: 'profile.md',
      ),
    );
  }
  final yamlSource = _firstYamlFence(document.body);
  if (yamlSource == null) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: rules.profileDeclarationReadable,
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
        descriptor: rules.profileDeclarationReadable,
        message: 'The first fenced yaml declaration in profile.md is invalid.',
        path: 'profile.md',
      ),
    );
  }
  if (parsed is! Map) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        descriptor: rules.profileDeclarationFields,
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
          descriptor: rules.profileDeclarationFields,
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

ProfileFinding? _validateOkfBinding(
  Map<String, String> declaration,
  OkfBundleLoadResult loaded,
  String release,
) {
  Object? rootVersion;
  final rootIndex = loaded.indexes['index.md'];
  if (rootIndex != null) {
    try {
      rootVersion = OkfDocument.parse(rootIndex).frontmatter['okf_version'];
    } on OkfDocumentException {
      // The independent OKF result reports the malformed reserved document;
      // with no readable root binding, the finding below reports.
    }
  }
  if (declaration['okf_version'] == supportedOkfRelease &&
      rootVersion == supportedOkfRelease) {
    return null;
  }
  return ProfileFinding(
    descriptor: rules.okfReleaseBinding,
    message:
        'The declaration, root index, and Profile release must all bind '
        'to OKF 0.2.',
    path: 'profile.md',
    profileRelease: release,
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

final class _DeclarationRead {
  const _DeclarationRead.values(this.values) : finding = null;
  const _DeclarationRead.finding(this.finding) : values = null;

  final Map<String, String>? values;
  final ProfileFinding? finding;
}
