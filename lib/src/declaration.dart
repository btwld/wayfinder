import 'package:okf/okf.dart';

/// The profile-layer sidecar reserved at the root of a governed bundle.
const okfProfileDeclarationFilename = 'profile.yaml';

/// The governance declaration stored in a bundle's `profile.yaml` sidecar.
final class OkfProfileDeclaration {
  /// Creates an in-memory bundle profile declaration.
  OkfProfileDeclaration({
    required this.profile,
    required this.version,
    required this.okfVersion,
    Iterable<OkfFindingSuppression> suppressions =
        const <OkfFindingSuppression>[],
  }) : suppressions = List<OkfFindingSuppression>.unmodifiable(suppressions);

  /// The governing profile name.
  final String profile;

  /// The governing profile release.
  final String version;

  /// The base OKF version expected by the bundle.
  final String okfVersion;

  /// Finding suppressions passed as data to the upstream Verdict contract.
  final List<OkfFindingSuppression> suppressions;
}
