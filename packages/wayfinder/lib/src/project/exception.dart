/// A failure a host can act on: [code] is a stable kebab-case identifier,
/// and [message] a sentence that says what happened and names no command
/// (ADR-0018). The command line prints it and adds what to run; a host
/// words its own remedy from the code and, where one is typed, the
/// exception's data.
///
/// The project library throws these codes:
///
/// - `bundle-name-invalid`, `bundle-unknown`, `bundle-ambiguous`,
///   `bundle-missing`, `bundle-escapes`, `bundles-missing` and
///   `config-invalid` while discovering a project's bundles;
/// - the `DiagnosticCode` value a `WayfinderProfileResolutionException`
///   carries, such as `profile-unresolved`, or `profile-timeout` when reading
///   a Profile package ran past the resolver's bound; its `remedy` says when
///   selecting new revisions fixes it, and a
///   `ProfileSkillDirectoriesException` names the skill directories `get`
///   may not replace;
/// - `resolution-busy`, a `ProfileResolutionBusyException`, when another
///   `get` holds the project's lock, or the Profile cache stays locked past
///   its timeout;
/// - `resolution-stale` when the configuration, lock or Profile cache changed
///   after a plan;
/// - `fetch-required`, a `ProfileFetchRequiredException`, when a plan would
///   clone or refresh a Profile source that the request is offline for or
///   its fetch policy refused;
/// - `lock-change-required`, a `ProfileLockChangeRequiredException`, when a
///   locked-only plan would change `wayfinder.lock`;
/// - from `package:wayfinder/adoption.dart`: `adoption-invalid`,
///   `adoption-conflict`, `adoption-stale` and `adoption-failed`;
/// - `data-directory-unavailable` when no data directory can be located;
/// - `git-timeout` when a Git command writes nothing for its timeout, and
///   `git-output-too-large` when it writes more stdout than its limit;
/// - `cancelled` when a `WayfinderCancellation` stopped the operation; a
///   host's `GitRunner` throws [WayfinderException.cancelled] for it too.
///
/// `package:wayfinder/authoring.dart` adds `write-refused`, `write-stale`
/// and the codes of its `KnowledgeChangeException`. Other Wayfinder packages
/// add their own codes.
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
