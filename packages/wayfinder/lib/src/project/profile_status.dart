import '../diagnostics.dart';
import '../profile_package.dart';
import '../wayfinder_config.dart';
import 'exception.dart';
import 'profile_resolver.dart';
import 'profile_skills.dart';

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

/// What would change in `wayfinder.lock`, and why, when resolving cannot
/// keep it as written: [ProfileBindingStatus.lockChange] offline, and
/// [ProfileLockChangeRequiredException.change] once a locked-only plan
/// refuses.
final class ProfileLockChange {
  const ProfileLockChange(
    this.kind,
    this.reason, {
    this.profile,
    this.packages = const [],
  });

  final ProfileLockChangeKind kind;

  /// The sentence that says why, naming no command.
  final String reason;

  /// The binding whose chain the lock does not hold as resolving needs it,
  /// when one binding is the reason; null for a lock that is missing or
  /// whose configuration changed, which concerns every binding.
  final ProfileId? profile;

  /// The lock entries that would change, by Profile id, when the reason
  /// names them: those no chain reaches, and those whose package declares
  /// another release or parent.
  final List<ProfileId> packages;

  /// How [WayfinderProfileResolver.status] reports a binding for which the
  /// lock would change this way.
  ProfileBindingState get state => kind == ProfileLockChangeKind.lockMissing
      ? ProfileBindingState.lockMissing
      : ProfileBindingState.lockStale;

  Map<String, Object?> toJson() => {
    'kind': kind.wireValue,
    'reason': reason,
    'profile': profile?.value,
    'packages': [for (final id in packages) id.value],
  };
}

/// Whether a chain member's local copy is on this machine, as
/// [WayfinderProfileResolver.status] finds it offline: the mirror of its
/// source and its package file at the locked commit, both in the Profile
/// cache.
///
/// A locked-only plan contacts [location] only to clone a mirror that is
/// not there, or to refresh one that lacks the locked commit, which only
/// Git can tell; a plan that read the commit from the mirror left it there,
/// so a mirror is missing the commit only when its source rewrote history.
/// [hasPackage] is what [WayfinderProfileResolver.select] reads: with the
/// mirror but without it, as in a cache Wayfinder 0.2 wrote,
/// [WayfinderProfileResolver.restoreCachedPackages] copies it from the
/// mirror without fetching.
final class ProfileLocalCopy {
  const ProfileLocalCopy({
    required this.locked,
    required this.location,
    required this.hasMirror,
    required this.hasPackage,
  });

  final LockedPackage locked;

  /// Where Git reaches the member's source,
  /// [WayfinderProfileSource.locationOf] its `git`: the location a
  /// [ProfileFetch] for it names.
  final String location;

  /// The source's mirror is in the Profile cache.
  final bool hasMirror;

  /// The member's package file at the locked commit is in the Profile cache.
  final bool hasPackage;

  Map<String, Object?> toJson() => {
    'id': locked.id.value,
    'location': location,
    'has_mirror': hasMirror,
    'has_package': hasPackage,
  };
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
    this.copies = const [],
    this.lockChange,
    this.diagnostic,
    this.notes = const [],
    this.skillDirectories = const [],
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

  /// One [ProfileLocalCopy] per member of [chain], root first: whether its
  /// source's mirror and its package file are in the Profile cache, so a
  /// consent gate can name the sources a locked-only plan will contact.
  final List<ProfileLocalCopy> copies;

  /// Why resolving would change `wayfinder.lock` for this binding, as a
  /// locked-only plan would refuse it with `lock-change-required`; null
  /// unless [state] is [ProfileBindingState.lockMissing] or
  /// [ProfileBindingState.lockStale].
  final ProfileLockChange? lockChange;

  /// The error `select` reports for the binding's bundles, with its
  /// `wayfinder/` code and message; null when [state] is
  /// [ProfileBindingState.resolved]. Its message names no command; its
  /// [EngineDiagnostic.remedy] says when resolving the Profiles again
  /// fixes it.
  final EngineDiagnostic? diagnostic;

  /// The warnings `select` reports beside a selection, such as
  /// `profile-skill-stale` for a chain member whose installed skill is
  /// missing or not at its locked commit.
  final List<EngineDiagnostic> notes;

  /// Every directory a skill of [chain] installs into, with its state, for
  /// each member whose package ships a skill, root first and then in
  /// [ProfileSkills.roots] order: the data behind the `profile-skill-stale`
  /// notes, and the protected paths `get` would write or refuse. Read only
  /// once the chain's packages are, so empty unless [state] is
  /// [ProfileBindingState.resolved].
  final List<ProfileSkillDirectory> skillDirectories;

  Map<String, Object?> toJson() => {
    'id': id.value,
    'state': state.wireValue,
    'source': source.toJson(),
    'applies_to': appliesTo,
    'chain': [
      for (final locked in chain) {'id': locked.id.value, ...locked.toJson()},
    ],
    'missing': [for (final locked in missing) locked.id.value],
    'copies': [for (final copy in copies) copy.toJson()],
    'lock_change': lockChange?.toJson(),
    'diagnostic': diagnostic?.toJson(),
    'notes': [for (final note in notes) note.toJson()],
    'skill_directories': [
      for (final directory in skillDirectories) directory.toJson(),
    ],
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
    this.lockChange,
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;
  final List<ProfileBindingStatus> bindings;

  /// Why a locked-only plan would refuse with `lock-change-required` before
  /// it runs any Git command, or why the lock cannot be read; null when the
  /// lock holds exactly the chain each binding names. Beside each binding's
  /// own [ProfileBindingStatus.lockChange], it reports a lock entry that no
  /// configured chain reaches. A package that disagrees with its lock entry
  /// is found only once it is read: a binding's
  /// [ProfileBindingStatus.lockChange] reports it for a package in the
  /// cache, and a plan for one it fetches.
  final ProfileLockChange? lockChange;

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
    'lock_change': lockChange?.toJson(),
    'profiles': [for (final binding in bindings) binding.toJson()],
  };
}

/// `lock-change-required`: a locked-only plan
/// ([WayfinderProfileResolver.plan] with `lockedOnly`) would change
/// `wayfinder.lock`, so it was refused. [change] says what and why, as
/// data; the message ends with its reason. Resolving the Profiles without
/// `lockedOnly` writes the lock the project needs, which a person decides
/// deliberately.
final class ProfileLockChangeRequiredException extends WayfinderException {
  ProfileLockChangeRequiredException(this.change)
    : super(
        'lock-change-required',
        'Resolving would change wayfinder.lock, which a locked-only plan '
            'never does: ${change.reason}',
      );

  /// What would change in the lock, and why.
  final ProfileLockChange change;

  /// How [WayfinderProfileResolver.status] would report it:
  /// [ProfileBindingState.lockMissing] or [ProfileBindingState.lockStale].
  ProfileBindingState get state => change.state;

  /// The binding whose chain the lock does not hold as resolving needs it,
  /// when one binding is the reason.
  ProfileId? get profile => change.profile;
}
