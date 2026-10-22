import '../diagnostics.dart';
import '../profile_package.dart';
import '../wayfinder_config.dart';
import 'exception.dart';
import 'profile_resolver.dart';

/// Where one `wayfinder.json` binding's Profile stands on this machine, as
/// [WayfinderProfileResolver.status] reads it offline. Each state is what
/// [WayfinderProfileResolver.select] does for the binding's bundles, and each
/// but [resolved] is a reason it selects nothing.
enum ProfileBindingState {
  /// `select` selects the chain: the lock is current and holds it, and every
  /// package is in the Profile cache, parses and composes.
  resolved('resolved'),

  /// There is no `wayfinder.lock`, or it cannot be read or parsed. `get`
  /// writes it, fetching what the Profile cache lacks.
  lockMissing('lock-missing'),

  /// `wayfinder.lock` does not match: `wayfinder.json` changed after `get`,
  /// the lock lacks the binding's chain or records another source for it,
  /// or a package declares another release or parent than the lock records.
  /// `get` writes the lock again and keeps each locked commit whose source
  /// is unchanged.
  lockStale('lock-stale'),

  /// The lock is current, but a package of the chain is not in the Profile
  /// cache or cannot be read from it, as on a machine where `get` never ran
  /// for it. A locked-only plan ([WayfinderProfileResolver.plan] with
  /// `lockedOnly`) fetches exactly the locked commits.
  cacheMissing('cache-missing'),

  /// A package of the chain is malformed (`profile-invalid`); the Profile is
  /// what needs a fix.
  packageInvalid('package-invalid'),

  /// A package of the chain is for another engine (`profile-unsupported`);
  /// upgrading wayfinder reads it.
  packageUnsupported('package-unsupported'),

  /// Reading a package of the chain, its rule tests included, ran past the
  /// resolver's `packageTimeout` (`profile-timeout`).
  packageTimeout('package-timeout'),

  /// The chain and the project's additions do not compose
  /// (`profile-composition`).
  compositionFailed('composition-failed');

  const ProfileBindingState(this.wireValue);

  /// The stable value [ProfileBindingStatus.toJson] reports.
  final String wireValue;
}

/// One binding of [ProfileResolutionStatus]: the Profile `wayfinder.json`
/// names under [id], for the bundles it [appliesTo], and its [state].
final class ProfileBindingStatus {
  const ProfileBindingStatus({
    required this.id,
    required this.source,
    required this.appliesTo,
    required this.state,
    this.chain = const [],
    this.missing = const [],
    this.diagnostic,
    this.notes = const [],
  });

  final ProfileId id;

  /// The source as `wayfinder.json` names it.
  final WayfinderProfileSource source;

  /// The bundle paths the binding applies to, relative to the project root
  /// and normalized, as in `wayfinder.json`.
  final List<String> appliesTo;

  final ProfileBindingState state;

  /// The chain the lock records for [id], root ancestor first, once the lock
  /// is current and records the configured source for it; empty for
  /// [ProfileBindingState.lockMissing] and for a lock that is stale before
  /// any package is read.
  final List<LockedPackage> chain;

  /// The members of [chain] whose package file is not in the Profile cache,
  /// root first: the commits a locked-only plan has to bring in.
  final List<LockedPackage> missing;

  /// The error `select` reports for the binding's bundles, with its
  /// `wayfinder/` code and message; null when [state] is
  /// [ProfileBindingState.resolved].
  final EngineDiagnostic? diagnostic;

  /// The warnings `select` reports beside a selection, such as
  /// `profile-skill-stale` for a chain member whose installed skill is
  /// missing or not at its locked commit.
  final List<EngineDiagnostic> notes;

  Map<String, Object?> toJson() => {
    'id': id.value,
    'state': state.wireValue,
    'source': source.toJson(),
    'applies_to': appliesTo,
    'chain': [
      for (final locked in chain) {'id': locked.id.value, ...locked.toJson()},
    ],
    'missing': [for (final locked in missing) locked.id.value],
    'diagnostic': diagnostic?.toJson(),
    'notes': [for (final note in notes) note.toJson()],
  };
}

/// Where every Profile of a project stands on this machine, from
/// [WayfinderProfileResolver.status]: one [ProfileBindingStatus] per
/// `wayfinder.json` binding, in id order.
final class ProfileResolutionStatus {
  const ProfileResolutionStatus({
    required this.projectRoot,
    required this.configPath,
    required this.lockPath,
    required this.bindings,
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;
  final List<ProfileBindingStatus> bindings;

  /// Whether `select` selects every binding's chain.
  bool get resolved => bindings.every(
    (binding) => binding.state == ProfileBindingState.resolved,
  );

  /// The status of the binding [id]; null when `wayfinder.json` has none.
  ProfileBindingStatus? of(ProfileId id) =>
      bindings.where((binding) => binding.id == id).firstOrNull;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'configuration': configPath,
    'lock': lockPath,
    'resolved': resolved,
    'profiles': [for (final binding in bindings) binding.toJson()],
  };
}

/// `lock-change-required`: a locked-only plan
/// ([WayfinderProfileResolver.plan] with `lockedOnly`) would change
/// `wayfinder.lock`, so it was refused. [state] says why, as
/// [WayfinderProfileResolver.status] would: [ProfileBindingState.lockMissing]
/// or [ProfileBindingState.lockStale]. `get` writes the lock the project
/// needs, which a person resolves deliberately.
final class ProfileLockChangeRequiredException extends WayfinderException {
  const ProfileLockChangeRequiredException(
    this.state,
    String reason, {
    this.profile,
  }) : super(
         'lock-change-required',
         'Resolving would change wayfinder.lock, which a locked-only plan '
             'never does: $reason',
       );

  final ProfileBindingState state;

  /// The binding whose chain the lock does not hold as resolving needs it,
  /// when one binding is the reason.
  final ProfileId? profile;
}
