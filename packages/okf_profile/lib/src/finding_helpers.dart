import 'profile_finding.dart';
import 'profile_release.dart';
import 'profile_rule_descriptors.dart';

/// Builds the finding for one deterministic Profile rule assessed under the
/// supported release.
///
/// The descriptor is the finding's authority for id, severity, and rule
/// reference, so a call site names only the rule, the observation, and where
/// it was made.
ProfileFinding profileFinding(
        ProfileRuleDescriptor rule, String message, String path) =>
    ProfileFinding(
      descriptor: rule,
      message: message,
      path: path,
      profileRelease: supportedProfileRelease,
    );

String? nonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
