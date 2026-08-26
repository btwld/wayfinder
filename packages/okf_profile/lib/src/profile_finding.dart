import 'package:okf/okf.dart';

/// A deterministic Concepta Profile finding.
///
/// Projects into okf's finding model ([toOkfFinding]): the id uses okf's
/// frozen `<namespace>/<code>` grammar in the `concepta-profile` namespace,
/// severities are okf's two tiers, and the location is an okf location. The
/// Profile release and normative rule reference ride alongside, because guide
/// §4.2 requires every Profile finding to name them.
final class ProfileFinding {
  const ProfileFinding({
    required this.id,
    required this.message,
    required this.rule,
    this.severity = OkfFindingSeverity.error,
    this.profileRelease,
    this.path = 'profile.md',
    this.line,
    this.column,
  });

  final String id;
  final String message;
  final String rule;
  final OkfFindingSeverity severity;
  final String? profileRelease;
  final String path;
  final int? line;
  final int? column;

  OkfFindingLocation get _location =>
      OkfFindingLocation(path: path, line: line, column: column);

  /// This finding as an okf finding value, for canonical ordering and any
  /// consumer that speaks the okf contract.
  OkfFinding toOkfFinding() => OkfFinding(
        id: OkfFindingId.parse(id),
        severity: severity,
        message: message,
        location: _location,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        ...toOkfFinding().toJson(),
        'profile_release': profileRelease,
        'rule': rule,
      };

  String toText() {
    final release = profileRelease == null ? '' : '$profileRelease ';
    return '$_location: ${severity.wireValue} $id ($release$rule): $message';
  }
}
