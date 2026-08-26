import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:yaml/yaml.dart';

import 'concept_rules.dart';
import 'profile_finding.dart';
import 'profile_release.dart';
import 'structure_rules.dart';

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

  factory ProfileValidationResult.blockedByOkf(OkfSpecValidation validation) =>
      ProfileValidationResult._(
        okfValidation: validation,
        profileRelease: null,
        profileState: ProfileState.blockedByOkf,
        findings: const <ProfileFinding>[],
        automatedGateState: AutomatedGateState.fail,
      );

  factory ProfileValidationResult.undispatched(
    OkfSpecValidation validation,
    ProfileFinding finding,
  ) =>
      ProfileValidationResult._(
        okfValidation: validation,
        profileRelease: null,
        profileState: ProfileState.unsupported,
        findings: <ProfileFinding>[finding],
        automatedGateState: AutomatedGateState.unsupported,
      );

  factory ProfileValidationResult.unsupported(
    OkfSpecValidation validation,
    String release,
  ) =>
      ProfileValidationResult._(
        okfValidation: validation,
        profileRelease: release,
        profileState: ProfileState.unsupported,
        findings: const <ProfileFinding>[],
        automatedGateState: AutomatedGateState.unsupported,
      );

  factory ProfileValidationResult.assessed(
    OkfSpecValidation validation,
    Iterable<ProfileFinding> findings,
  ) {
    final stableFindings = List<ProfileFinding>.unmodifiable(
      findings.toList()
        ..sort(
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
      profileRelease: supportedProfileRelease,
      profileState: failed ? ProfileState.fail : ProfileState.pass,
      findings: stableFindings,
      automatedGateState:
          failed ? AutomatedGateState.fail : AutomatedGateState.pass,
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
        'automated_gate': <String, Object>{
          'state': automatedGateState.wireValue,
        },
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

  Future<ProfileValidationResult> validate(String bundlePath) async {
    final loaded = await loader.inspect(bundlePath);
    final validation = loaded.validate();
    if (!validation.isConformant) {
      return ProfileValidationResult.blockedByOkf(validation);
    }
    final declaration = _readDeclaration(loaded);
    if (declaration.finding case final finding?) {
      return ProfileValidationResult.undispatched(validation, finding);
    }
    final values = declaration.values!;
    final release = values['concepta_profile']!;
    if (release != supportedProfileRelease) {
      return ProfileValidationResult.unsupported(validation, release);
    }
    return ProfileValidationResult.assessed(
      validation,
      <ProfileFinding>[
        if (_validateOkfBinding(values, loaded) case final finding?) finding,
        ...validateConceptRules(loaded),
        ...validateStructureRules(loaded),
      ],
    );
  }
}

_DeclarationRead _readDeclaration(OkfBundleLoadResult loaded) {
  final document = loaded.documents['profile.md'];
  if (document == null) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        id: 'concepta-profile/profile-declaration-present',
        message: 'The bundle must contain profile.md.',
        rule: '§11',
      ),
    );
  }
  final yamlSource = _firstYamlFence(document.body);
  if (yamlSource == null) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        id: 'concepta-profile/profile-declaration-readable',
        message: 'profile.md must contain a fenced yaml declaration.',
        rule: '§11',
      ),
    );
  }
  Object? parsed;
  try {
    parsed = loadYaml(yamlSource);
  } on YamlException {
    return const _DeclarationRead.finding(
      ProfileFinding(
        id: 'concepta-profile/profile-declaration-readable',
        message: 'The first fenced yaml declaration in profile.md is invalid.',
        rule: '§11',
      ),
    );
  }
  if (parsed is! Map) {
    return const _DeclarationRead.finding(
      ProfileFinding(
        id: 'concepta-profile/profile-declaration-fields',
        message: 'The Profile declaration must be a YAML mapping.',
        rule: '§11',
      ),
    );
  }
  final values = <String, String>{};
  for (final key in const <String>['concepta_profile', 'okf_version']) {
    final value = parsed[key];
    if (value is! String || value.trim().isEmpty) {
      return const _DeclarationRead.finding(
        ProfileFinding(
          id: 'concepta-profile/profile-declaration-fields',
          message: 'The Profile declaration must contain non-empty string '
              'values for concepta_profile and okf_version.',
          rule: '§11',
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
) {
  Object? rootVersion;
  final rootIndex = loaded.indexes['index.md'];
  if (rootIndex != null) {
    rootVersion = OkfDocument.parse(rootIndex).frontmatter['okf_version'];
  }
  if (declaration['okf_version'] == supportedOkfRelease &&
      rootVersion == supportedOkfRelease) {
    return null;
  }
  return const ProfileFinding(
    id: 'concepta-profile/okf-release-binding',
    message: 'The declaration, root index, and Profile release must all bind '
        'to OKF 0.2.',
    rule: '§11',
    profileRelease: supportedProfileRelease,
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
