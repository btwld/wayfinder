import 'profile_finding.dart';
import 'profile_release.dart';
import 'profile_rule_descriptors.dart';

/// Builds the finding for one deterministic Profile rule.
///
/// The descriptor registry owns the rule's severity and normative rule
/// reference, so a call site names only the rule, the observation, and where
/// it was made.
ProfileFinding profileFinding(String slug, String message, String path) {
  final id = 'concepta-profile/$slug';
  final descriptor = profileRuleDescriptor(id);
  if (descriptor == null) {
    throw ArgumentError.value(slug, 'slug', 'No profile rule descriptor');
  }
  return ProfileFinding(
    id: id,
    message: message,
    rule: descriptor.rule,
    severity: descriptor.severity,
    profileRelease: supportedProfileRelease,
    path: path,
  );
}

String? nonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
