/// A failure a host can act on: [code] is a stable kebab-case identifier,
/// and [message] is the sentence the command line prints.
///
/// The project library throws these codes:
///
/// - `bundle-name-invalid`, `bundle-unknown`, `bundle-ambiguous`,
///   `bundle-missing`, `bundle-escapes`, `bundles-missing` and
///   `config-invalid` while discovering a project's bundles;
/// - the `DiagnosticCode` value a `WayfinderProfileResolutionException`
///   carries, such as `profile-unresolved`;
/// - `resolution-busy` when another `get` holds the project's lock, or the
///   Profile cache stays locked past its timeout;
/// - `resolution-stale` when the configuration, lock or Profile cache changed
///   after a plan;
/// - `fetch-required`, a `ProfileFetchRequiredException`, when a plan would
///   clone or refresh a Profile source that the request is offline for or
///   its fetch policy refused;
/// - from `package:wayfinder/adoption.dart`: `adoption-invalid`,
///   `adoption-conflict`, `adoption-stale` and `adoption-failed`;
/// - `data-directory-unavailable` when no data directory can be located;
/// - `git-timeout` when a Git command writes nothing for its timeout;
/// - `cancelled` when a `WayfinderCancellation` stopped the operation; a
///   host's `GitRunner` throws [WayfinderException.cancelled] for it too.
///
/// Other Wayfinder packages add their own codes.
class WayfinderException implements Exception {
  const WayfinderException(this.code, this.message);

  /// The `cancelled` failure of an operation a `WayfinderCancellation`
  /// stopped.
  const WayfinderException.cancelled()
    : this('cancelled', 'The operation was cancelled.');

  final String code;
  final String message;

  @override
  String toString() => message;
}
