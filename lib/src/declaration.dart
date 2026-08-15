import 'package:okf/okf.dart';

import 'release.dart';

/// The profile-layer sidecar reserved at the root of a governed bundle.
const okfProfileDeclarationFilename = 'profile.yaml';

/// The governance declaration stored in a bundle's `profile.yaml` sidecar.
final class OkfProfileDeclaration {
  /// Creates an in-memory bundle profile declaration.
  OkfProfileDeclaration({
    required this.release,
    required this.okfVersion,
    Iterable<OkfFindingSuppression> suppressions =
        const <OkfFindingSuppression>[],
  }) : suppressions = List<OkfFindingSuppression>.unmodifiable(suppressions);

  /// The governing profile release, from the `profile` and `version` fields.
  final OkfProfileRelease release;

  /// The base OKF version expected by the bundle.
  final String okfVersion;

  /// Finding suppressions passed as data to the upstream Verdict contract.
  final List<OkfFindingSuppression> suppressions;
}
