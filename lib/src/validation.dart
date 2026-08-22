import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:yaml/yaml.dart';

const supportedProfileRelease = '2026.2';
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
  pass('PASS', 0),
  fail('FAIL', 1),
  unsupported('UNSUPPORTED', 2);

  const AutomatedGateState(this.wireValue, this.exitCode);

  final String wireValue;
  final int exitCode;
}

final class ProfileFinding {
  const ProfileFinding({
    required this.id,
    required this.message,
    required this.rule,
    this.profileRelease,
    this.path = 'profile.md',
  });

  final String id;
  final String message;
  final String rule;
  final String? profileRelease;
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'severity': 'error',
        'profile_release': profileRelease,
        'rule': rule,
        'path': path,
        'message': message,
      };

  String toText() {
    final release = profileRelease == null ? '' : '$profileRelease ';
    return '$path: error $id ($release$rule): $message';
  }
}

final class ProfileValidationResult {
  ProfileValidationResult._({
    required this.okfLoadIssues,
    required this.okfReport,
    required this.profileRelease,
    required this.profileState,
    required Iterable<ProfileFinding> findings,
    required this.automatedGateState,
  }) : findings = List<ProfileFinding>.unmodifiable(findings);

  factory ProfileValidationResult.blockedByOkf(
    OkfBundleLoadResult loaded,
    OkfValidationReport report,
  ) =>
      ProfileValidationResult._(
        okfLoadIssues: loaded.issues,
        okfReport: report,
        profileRelease: null,
        profileState: ProfileState.blockedByOkf,
        findings: const <ProfileFinding>[],
        automatedGateState: AutomatedGateState.fail,
      );

  factory ProfileValidationResult.undispatched(
    OkfBundleLoadResult loaded,
    OkfValidationReport report,
    ProfileFinding finding,
  ) =>
      ProfileValidationResult._(
        okfLoadIssues: loaded.issues,
        okfReport: report,
        profileRelease: null,
        profileState: ProfileState.unsupported,
        findings: <ProfileFinding>[finding],
        automatedGateState: AutomatedGateState.unsupported,
      );

  factory ProfileValidationResult.unsupported(
    OkfBundleLoadResult loaded,
    OkfValidationReport report,
    String release,
  ) =>
      ProfileValidationResult._(
        okfLoadIssues: loaded.issues,
        okfReport: report,
        profileRelease: release,
        profileState: ProfileState.unsupported,
        findings: const <ProfileFinding>[],
        automatedGateState: AutomatedGateState.unsupported,
      );

  factory ProfileValidationResult.assessed(
    OkfBundleLoadResult loaded,
    OkfValidationReport report,
    ProfileFinding? finding,
  ) =>
      ProfileValidationResult._(
        okfLoadIssues: loaded.issues,
        okfReport: report,
        profileRelease: supportedProfileRelease,
        profileState: finding == null ? ProfileState.pass : ProfileState.fail,
        findings: <ProfileFinding>[if (finding != null) finding],
        automatedGateState:
            finding == null ? AutomatedGateState.pass : AutomatedGateState.fail,
      );

  final List<OkfBundleLoadIssue> okfLoadIssues;
  final OkfValidationReport okfReport;
  final String? profileRelease;
  final ProfileState profileState;
  final List<ProfileFinding> findings;
  final AutomatedGateState automatedGateState;

  OkfState get okfState => okfLoadIssues.isEmpty && okfReport.isValid
      ? OkfState.pass
      : OkfState.fail;

  int get exitCode => automatedGateState.exitCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'okf': <String, Object?>{
          'state': okfState.wireValue,
          'load_issues': okfLoadIssues.map(_loadIssueJson).toList(),
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
    for (final issue in okfLoadIssues) {
      yield issue.toString();
    }
    for (final diagnostic in okfReport.diagnostics) {
      yield diagnostic.toString();
    }
    yield 'OKF Report: ${okfReport.errorCount} error(s), '
        '${okfReport.warningCount} warning(s).';
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
}

final class ProfileValidator {
  const ProfileValidator({
    this.loader = const OkfBundleLoader(),
    this.okfValidator = const OkfValidator(),
  });

  final OkfBundleLoader loader;
  final OkfValidator okfValidator;

  Future<ProfileValidationResult> validate(String bundlePath) async {
    final loaded = await loader.inspect(bundlePath);
    final okfReport = okfValidator.validate(loaded.bundle);
    if (loaded.hasIssues || !okfReport.isValid) {
      return ProfileValidationResult.blockedByOkf(loaded, okfReport);
    }

    final declaration = _readDeclaration(loaded);
    if (declaration.finding case final finding?) {
      return ProfileValidationResult.undispatched(loaded, okfReport, finding);
    }

    final values = declaration.values!;
    final release = values['concepta_profile']!;
    if (release != supportedProfileRelease) {
      return ProfileValidationResult.unsupported(loaded, okfReport, release);
    }

    return ProfileValidationResult.assessed(
      loaded,
      okfReport,
      _validateOkfBinding(values, loaded),
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
      return _DeclarationRead.finding(
        const ProfileFinding(
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
          if (nested != null) {
            return nested;
          }
        }
      }
    }
    return null;
  }

  return find(nodes);
}

Map<String, Object> _loadIssueJson(OkfBundleLoadIssue issue) =>
    <String, Object>{
      'code': issue.code,
      'message': issue.message,
      'path': issue.path,
      if (issue.line != null) 'line': issue.line!,
      if (issue.column != null) 'column': issue.column!,
    };

final class _DeclarationRead {
  const _DeclarationRead.values(this.values) : finding = null;

  const _DeclarationRead.finding(this.finding) : values = null;

  final Map<String, String>? values;
  final ProfileFinding? finding;
}
