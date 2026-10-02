import 'package:okf/okf.dart';

import 'profile_rule_descriptors.dart';

/// A deterministic finding of a Profile rule.
///
/// Built from the descriptor of the rule that reported it, which is the
/// finding's single authority for id, severity and help link. Projects
/// into okf's finding model ([toOkfFinding]): the id uses okf's frozen
/// `<namespace>/<code>` grammar with the Profile id as the namespace,
/// severities are okf's two tiers, and the location is an okf location. The
/// Profile release rides alongside, because guide §4.2 requires every
/// Profile finding to name the release it assessed under.
final class ProfileFinding {
  const ProfileFinding({
    required FindingDescriptor descriptor,
    required this.message,
    required this.path,
    required this.profileRelease,
  }) : _descriptor = descriptor;

  final FindingDescriptor _descriptor;

  /// The rule that reported this finding: an error or advisory rule, since
  /// a note rule reports [ProfileSummaryEntry]s instead.
  ProfileRuleDescriptor get descriptor => _descriptor.descriptor;

  final String message;

  /// Bundle-relative path.
  final String path;

  /// The release of the package whose rule reported this finding.
  final String profileRelease;

  String get id => descriptor.id;
  OkfFindingSeverity get severity => _descriptor.severity;
  Uri? get helpUri => descriptor.helpUri;

  OkfFindingLocation get _location => OkfFindingLocation(path: path);

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
    if (helpUri case final uri?) 'help_uri': '$uri',
  };

  String toText() =>
      '$_location: ${severity.wireValue} $id ($profileRelease): $message';
}

/// Something a note rule found that the Profile permits, such as an
/// unresolved planned link. A summary entry is not a finding, so it carries
/// no severity and never affects the Profile state, the gate or the exit
/// status. SARIF reports it as a result of kind `informational`.
final class ProfileSummaryEntry {
  const ProfileSummaryEntry({
    required this.descriptor,
    required this.message,
    required this.path,
    required this.profileRelease,
  });

  /// The note rule that reported this entry.
  final ProfileRuleDescriptor descriptor;

  final String message;

  /// Bundle-relative path.
  final String path;

  final String profileRelease;

  String get id => descriptor.id;
  Uri? get helpUri => descriptor.helpUri;

  OkfFindingLocation get _location => OkfFindingLocation(path: path);

  /// Canonical order without a severity: path, then id, then message, as
  /// okf orders findings that carry no line or column.
  static int compare(ProfileSummaryEntry left, ProfileSummaryEntry right) {
    final byPath = left.path.compareTo(right.path);
    if (byPath != 0) return byPath;
    final byId = left.id.compareTo(right.id);
    return byId != 0 ? byId : left.message.compareTo(right.message);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'message': message,
    'location': _location.toJson(),
    'profile_release': profileRelease,
    if (helpUri case final uri?) 'help_uri': '$uri',
  };

  String toText() => '$_location: note $id ($profileRelease): $message';
}
