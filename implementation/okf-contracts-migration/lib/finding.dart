/// A stable, namespaced identifier for an OKF finding.
///
/// IDs use one of three wire grammars: `okf/<code>` for base rules,
/// `profile/<code>` for profile rules, and
/// `profile/frontmatter-<keyword>` for schema findings.
final class OkfFindingId {
  const OkfFindingId._(this.value);

  /// Creates an identifier owned by a base OKF rule.
  factory OkfFindingId.base(String code) =>
      OkfFindingId._('okf/${_validateSegment(code)}');

  /// Creates an identifier owned by a profile rule.
  factory OkfFindingId.profile(String code) =>
      OkfFindingId._('profile/${_validateSegment(code)}');

  /// Creates an identifier owned by a frontmatter schema keyword.
  factory OkfFindingId.frontmatter(String keyword) => OkfFindingId._(
        'profile/frontmatter-${_validateSegment(keyword)}',
      );

  /// Reads a finding identifier in one of the supported wire grammars.
  factory OkfFindingId.parse(String value) {
    const frontmatterPrefix = 'profile/frontmatter-';
    if (value.startsWith(frontmatterPrefix)) {
      return OkfFindingId.frontmatter(
        value.substring(frontmatterPrefix.length),
      );
    }
    const basePrefix = 'okf/';
    if (value.startsWith(basePrefix)) {
      return OkfFindingId.base(value.substring(basePrefix.length));
    }
    const profilePrefix = 'profile/';
    if (value.startsWith(profilePrefix)) {
      return OkfFindingId.profile(value.substring(profilePrefix.length));
    }
    throw FormatException('Unsupported finding ID namespace', value);
  }

  /// The stable representation used in text, JSON, and configuration.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OkfFindingId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The severity assigned by the rule that produced a finding.
enum OkfFindingSeverity {
  /// A base conformance violation.
  error,

  /// A non-base concern that fails only in strict mode.
  advisory,
}

/// A location within a logical OKF bundle.
///
/// Lines and columns are one-based. [pointer] is a JSON Pointer into parsed
/// document data when a source coordinate is not available.
final class OkfFindingLocation {
  /// Creates a bundle-relative finding location.
  const OkfFindingLocation({
    required this.logicalPath,
    this.line,
    this.column,
    this.pointer,
  });

  /// The POSIX-style path relative to the bundle root.
  final String logicalPath;

  /// The one-based source line, when known.
  final int? line;

  /// The one-based source column, when known.
  final int? column;

  /// A JSON Pointer locating parsed data, when applicable.
  final String? pointer;
}

/// A machine-readable problem found while loading or validating a bundle.
final class OkfFinding {
  /// Creates a finding.
  const OkfFinding({
    required this.id,
    required this.severity,
    required this.message,
    this.location,
  });

  /// The stable identifier owned by the finding contract.
  final OkfFindingId id;

  /// How the finding participates in a verdict.
  final OkfFindingSeverity severity;

  /// A human-readable explanation.
  final String message;

  /// The affected bundle location, when one is known.
  final OkfFindingLocation? location;
}

/// A suppression declared in the bundle's `profile.yaml` file.
final class OkfSuppression {
  /// Creates a suppression for [findingId].
  const OkfSuppression({required this.findingId, this.note});

  /// The stable finding identifier to suppress.
  final OkfFindingId findingId;

  /// Optional reviewer context for the temporary suppression.
  final String? note;
}

/// A finding and the suppression state assigned to it by a report.
final class OkfReportedFinding {
  /// Creates a reported finding.
  const OkfReportedFinding({required this.finding, this.suppression});

  /// The finding emitted by loading or validation.
  final OkfFinding finding;

  /// The matching declaration when this finding was suppressed.
  final OkfSuppression? suppression;

  /// Whether this finding is excluded from the failing set.
  bool get isSuppressed => suppression != null;
}

/// The pass/fail result consumed by CLI, MCP, and CI adapters.
enum OkfVerdict {
  /// No unsuppressed finding requires failure.
  passed(0),

  /// At least one unsuppressed finding requires failure.
  failed(1);

  const OkfVerdict(this.exitCode);

  /// The process exit code for validation adapters.
  final int exitCode;
}

/// Computes a verdict from findings, declarations, and strictness.
///
/// Unsuppressed errors fail in every mode. Unsuppressed advisories, including
/// `profile/unknown-profile-release`, fail only in strict mode. Suppressed
/// advisories do not fail, while base errors cannot be suppressed.
typedef OkfVerdictEvaluator = OkfVerdict Function(
  Iterable<OkfFinding> findings,
  Iterable<OkfSuppression> suppressions, {
  required bool strict,
});

/// The single report seam shared by all validation adapters.
abstract interface class OkfReport {
  /// Findings in deterministic order, including their suppression state.
  List<OkfReportedFinding> get findings;

  /// The verdict computed for this report's strictness setting.
  OkfVerdict get verdict;

  /// Projects the complete report to human-readable text.
  String toText();

  /// Projects the complete report to a JSON-compatible mapping.
  Map<String, Object?> toJson();
}

String _validateSegment(String value) {
  if (!_findingSegment.hasMatch(value)) {
    throw FormatException(
      'Finding ID segments must be lowercase kebab-case',
      value,
    );
  }
  return value;
}

final RegExp _findingSegment = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
