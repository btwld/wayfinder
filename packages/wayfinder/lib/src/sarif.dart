import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;

import 'diagnostics.dart';
import 'generated/published_schemas.g.dart';
import 'profile_finding.dart';
import 'profile_rule_descriptors.dart';
import 'validation.dart';

const _workingDirectory = 'WORKINGDIR';

const _schema =
    'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/'
    'sarif-schema-2.1.0.json';

/// [result] as a SARIF 2.1.0 log, carrying the same findings, summary
/// entries and diagnostics as its JSON.
///
/// Each finding is a result whose `ruleId` is the finding id, and each
/// summary entry a result of kind `informational`, whose level SARIF
/// §3.27.10 requires to be `none`. Each diagnostic is a notification on the
/// invocation: configuration diagnostics in `toolConfigurationNotifications`
/// and execution diagnostics in `toolExecutionNotifications`, described by
/// `driver.notifications`. `executionSuccessful` is false iff a diagnostic is
/// an error, which is when the gate cannot pass for want of an assessment.
///
/// A location inside the working directory is relative to the run's
/// `WORKINGDIR` base, so code scanning resolves it against a checkout when
/// validation runs at its root. One outside is an absolute file URI: a `..`
/// reference would resolve differently wherever a consumer placed the base.
/// Bundle locations join [bundlePath] as given. Every package in the
/// assessed chain supplies one rule descriptor per rule, fired or not,
/// naming the package's release and help link; OKF descriptors appear only
/// for the findings present. The okf package the engine generates indexes
/// with is a tool extension, so a change in generated output reads as an
/// engine upgrade rather than a Profile change.
Map<String, Object?> toSarif(
  ProfileValidationResult result, {
  required String bundlePath,
  required String toolVersion,
}) {
  final workingDirectory = p.current;
  Map<String, Object?> artifact(String file) {
    final absolute = p.normalize(p.absolute(file));
    if (!p.isWithin(workingDirectory, absolute)) {
      return {'uri': Uri.file(absolute).toString()};
    }
    return {
      'uri': Uri(
        pathSegments: p.split(p.relative(absolute, from: workingDirectory)),
      ).toString(),
      'uriBaseId': _workingDirectory,
    };
  }

  Map<String, Object?> inBundle(String path) =>
      artifact(p.join(bundlePath, path));

  final okfFindings = result.okfReport.findings;
  return _log(
    toolVersion: toolVersion,
    workingDirectory: workingDirectory,
    rules: [
      for (final id in {for (final finding in okfFindings) finding.id})
        _okfDescriptor(id),
      for (final package in result.chain)
        for (final rule in package.rules)
          _profileDescriptor(
            rule.descriptor,
            release: package.release,
            description: rule.description,
            category: rule.category.name,
          ),
    ],
    diagnostics: result.diagnostics,
    diagnosticArtifact: (location) => switch (location) {
      ProjectFileLocation(:final file) => artifact(file),
      BundleLocation(:final path) => inBundle(path),
    },
    results: [
      for (final finding in okfFindings)
        _result(
          finding.id.value,
          _level(finding.severity),
          finding.message,
          location: finding.location,
          artifact: inBundle,
        ),
      for (final finding in result.findings)
        _result(
          finding.id,
          _level(finding.severity),
          finding.message,
          location: OkfFindingLocation(path: finding.path),
          artifact: inBundle,
        ),
      for (final entry in result.summary ?? const <ProfileSummaryEntry>[])
        _result(
          entry.id,
          'none',
          entry.message,
          location: OkfFindingLocation(path: entry.path),
          artifact: inBundle,
          kind: 'informational',
        ),
    ],
    properties: {
      'okf_state': result.okfState.wireValue,
      'profile_release': result.profileRelease,
      'profile_state': result.profileState.wireValue,
      'gate': result.gate.wireValue,
    },
  );
}

/// The SARIF log of a run that stopped before it had a result: no results,
/// one `wayfinder/internal-error` execution notification.
Map<String, Object?> internalErrorSarif(
  String message, {
  required String toolVersion,
}) => _log(
  toolVersion: toolVersion,
  workingDirectory: p.current,
  rules: const [],
  diagnostics: [EngineDiagnostic(DiagnosticCode.internalError, message)],
  diagnosticArtifact: (_) => throw StateError('internal-error has no location'),
  results: const [],
  properties: {'gate': GateState.incomplete.wireValue},
);

Map<String, Object?> _log({
  required String toolVersion,
  required String workingDirectory,
  required List<Map<String, Object?>> rules,
  required List<EngineDiagnostic> diagnostics,
  required Map<String, Object?> Function(DiagnosticLocation) diagnosticArtifact,
  required List<Map<String, Object?>> results,
  required Map<String, Object?> properties,
}) {
  final codes = {
    for (final diagnostic in diagnostics) diagnostic.code,
  }.toList();
  List<Map<String, Object?>> notifications(DiagnosticChannel channel) => [
    for (final diagnostic in diagnostics)
      if (diagnostic.code.channel == channel)
        {
          'descriptor': {
            'id': diagnostic.id,
            'index': codes.indexOf(diagnostic.code),
          },
          'level': diagnostic.level.name,
          'message': {'text': diagnostic.message},
          if (diagnostic.location case final location?)
            'locations': [
              {
                'physicalLocation': {
                  'artifactLocation': diagnosticArtifact(location),
                },
              },
            ],
        },
  ];
  final configuration = notifications(DiagnosticChannel.configuration);
  final execution = notifications(DiagnosticChannel.execution);
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
            'rules': rules,
            if (codes.isNotEmpty)
              'notifications': [
                for (final code in codes)
                  {
                    'id': code.id,
                    'shortDescription': {'text': code.description},
                    'defaultConfiguration': {'level': code.level.name},
                  },
              ],
          },
          'extensions': [
            {'name': 'okf', 'version': okfPackageVersion},
          ],
        },
        'invocations': [
          {
            'executionSuccessful': !diagnostics.any((d) => d.isError),
            if (configuration.isNotEmpty)
              'toolConfigurationNotifications': configuration,
            if (execution.isNotEmpty) 'toolExecutionNotifications': execution,
          },
        ],
        'originalUriBaseIds': {
          _workingDirectory: {
            'uri': Uri.directory(workingDirectory).toString(),
          },
        },
        'results': results,
        'properties': properties,
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
  required String release,
  required String description,
  required String category,
}) => {
  'id': descriptor.id,
  'shortDescription': {'text': description},
  if (descriptor.helpUri case final uri?) 'helpUri': '$uri',
  'defaultConfiguration': {
    'level': switch (descriptor.severity.finding) {
      final severity? => _level(severity),
      null => 'none',
    },
  },
  'properties': {'category': category, 'profile_release': release},
};

Map<String, Object?> _result(
  String ruleId,
  String level,
  String message, {
  required OkfFindingLocation? location,
  required Map<String, Object?> Function(String path) artifact,
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
          'artifactLocation': artifact(location.path),
          if (location.line case final line?)
            'region': {'startLine': line, 'startColumn': ?location.column},
        },
      },
    ],
};
