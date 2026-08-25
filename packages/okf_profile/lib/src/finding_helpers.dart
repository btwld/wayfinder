import 'profile_finding.dart';
import 'profile_release.dart';

ProfileFinding profileError(
  String slug,
  String message,
  String rule,
  String path,
) =>
    ProfileFinding(
      id: 'concepta-profile/$slug',
      message: message,
      rule: rule,
      profileRelease: supportedProfileRelease,
      path: path,
    );

ProfileFinding profileAdvisory(
  String slug,
  String message,
  String rule,
  String path,
) =>
    ProfileFinding(
      id: 'concepta-profile/$slug',
      message: message,
      rule: rule,
      severity: ProfileFindingSeverity.advisory,
      profileRelease: supportedProfileRelease,
      path: path,
    );

String? nonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
