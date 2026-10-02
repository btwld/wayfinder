import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;

import 'profile_finding.dart';
import 'profile_rule_descriptors.dart';
import 'rules/catalog.dart';
import 'validation.dart';

const _schema =
    'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/'
    'sarif-schema-2.1.0.json';

/// [result] as a SARIF 2.1.0 log, carrying the same findings and summary
/// entries as its JSON.
///
/// Each finding is a result whose `ruleId` is the finding id, and each
/// summary entry a result of kind `informational`, whose level SARIF
/// §3.27.10 requires to be `none`. Locations are
/// relative to the working directory, joined from [bundlePath] as given (or
/// the project configuration file, for a finding about it), so code scanning
/// resolves them against a checkout when validation runs at its root. Every
/// catalog in the assessed chain supplies one rule descriptor per rule,
/// fired or not, naming the catalog's release; OKF and dispatch descriptors
/// appear only for the findings present.
Map<String, Object?> toSarif(
  ProfileValidationResult result, {
  required String bundlePath,
  required String toolVersion,
}) {
  final config = result.projectConfig;
  String uri(String path) {
    final file = config != null && path == config.reported
        ? config.file
        : p.join(bundlePath, path);
    return Uri(pathSegments: p.split(p.relative(file))).toString();
  }

  final okfFindings = result.okfReport.findings;
  final catalogs = result.catalogs ?? const <RuleCatalog>[];
  final catalogIds = {
    for (final catalog in catalogs)
      for (final rule in catalog.rules) rule.descriptor.id,
  };
  return {
    r'$schema': _schema,
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'wayfinder',
            'version': toolVersion,
            'informationUri': 'https://github.com/btwld/wayfinder',
            'rules': [
              for (final id in {for (final finding in okfFindings) finding.id})
                _okfDescriptor(id),
              for (final catalog in catalogs)
                for (final rule in catalog.rules)
                  _profileDescriptor(
                    rule.descriptor,
                    release: catalog.release,
                    description: rule.description,
                    category: rule.category.name,
                  ),
              for (final descriptor in {
                for (final finding in result.findings)
                  if (!catalogIds.contains(finding.id)) finding.descriptor,
              })
                _profileDescriptor(descriptor),
            ],
          },
        },
        'invocations': [
          {
            'executionSuccessful':
                result.automatedGateState != AutomatedGateState.unsupported,
          },
        ],
        'results': [
          for (final finding in okfFindings)
            _result(
              finding.id.value,
              _level(finding.severity),
              finding.message,
              location: finding.location,
              uri: uri,
            ),
          for (final finding in result.findings)
            _result(
              finding.id,
              _level(finding.severity),
              finding.message,
              location: OkfFindingLocation(path: finding.path),
              uri: uri,
            ),
          for (final entry in result.summary ?? const <ProfileSummaryEntry>[])
            _result(
              entry.id,
              'none',
              entry.message,
              location: OkfFindingLocation(path: entry.path),
              uri: uri,
              kind: 'informational',
            ),
        ],
        'properties': {
          'okf_state': result.okfState.wireValue,
          'profile_release': result.profileRelease,
          'profile_state': result.profileState.wireValue,
          'judgment_rules': 'UNASSESSED',
          'automated_gate': result.automatedGateState.wireValue,
        },
      },
    ],
  };
}

String _level(OkfFindingSeverity severity) => switch (severity) {
  OkfFindingSeverity.error => 'error',
  OkfFindingSeverity.advisory => 'warning',
};

Map<String, Object?> _okfDescriptor(OkfFindingId id) {
  final prose = okfSpecRuleDescriptors
      .where((descriptor) => descriptor.id == id)
      .firstOrNull
      ?.prose;
  return {
    'id': id.value,
    if (prose != null) 'shortDescription': {'text': prose},
  };
}

Map<String, Object?> _profileDescriptor(
  ProfileRuleDescriptor descriptor, {
  String? release,
  String? description,
  String? category,
}) => {
  'id': descriptor.id,
  if (description != null) 'shortDescription': {'text': description},
  'defaultConfiguration': {
    'level': switch (descriptor.severity.finding) {
      final severity? => _level(severity),
      null => 'none',
    },
  },
  'properties': {
    'category': ?category,
    'ref': descriptor.rule,
    'profile_release': ?release,
  },
};

Map<String, Object?> _result(
  String ruleId,
  String level,
  String message, {
  required OkfFindingLocation? location,
  required String Function(String path) uri,
  String? kind,
}) => {
  'ruleId': ruleId,
  'kind': ?kind,
  'level': level,
  'message': {'text': message},
  if (location != null)
    'locations': [
      {
        'physicalLocation': {
          'artifactLocation': {'uri': uri(location.path)},
          if (location.line case final line?)
            'region': {'startLine': line, 'startColumn': ?location.column},
        },
      },
    ],
};
