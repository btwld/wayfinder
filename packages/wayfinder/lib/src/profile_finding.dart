import 'package:okf/okf.dart';

import 'profile_rule_descriptors.dart';

/// A deterministic Concepta Profile finding.
///
/// Built from the descriptor of the rule that reported it, which is the
/// finding's single authority for id, severity, and normative rule reference.
/// Projects into okf's finding model ([toOkfFinding]): the id uses okf's
/// frozen `<namespace>/<code>` grammar in the `concepta-profile` namespace,
/// severities are okf's two tiers, and the location is an okf location. The
/// Profile release and normative rule reference ride alongside, because guide
/// §4.2 requires every Profile finding to name them.
final class ProfileFinding {
  const ProfileFinding({
    required this.descriptor,
    required this.message,
    required this.path,
    this.profileRelease,
  });

  /// The rule that reported this finding.
  final ProfileRuleDescriptor descriptor;

  final String message;

  /// Bundle-relative path of the observation.
  final String path;

  /// The Profile release the rule assessed under; null when the finding
  /// precedes release dispatch.
  final String? profileRelease;

  String get id => descriptor.id;
  OkfFindingSeverity get severity => descriptor.severity;
  String get rule => descriptor.rule;

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
    'rule': rule,
  };

  String toText() {
    final release = profileRelease == null ? '' : '$profileRelease ';
    return '$_location: ${severity.wireValue} $id ($release$rule): $message';
  }
}
