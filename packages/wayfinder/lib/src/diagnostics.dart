/// How severe a diagnostic is. Wire values follow SARIF notification levels.
enum DiagnosticLevel { error, warning, note }

/// Where SARIF reports a diagnostic: `toolConfigurationNotifications` for
/// problems with what the engine was asked to assess, and
/// `toolExecutionNotifications` for problems while assessing it.
enum DiagnosticChannel { configuration, execution }

/// The engine's own reports about a run, as opposed to Profile findings about
/// the bundle. The set is closed. No catalog can declare or suppress these,
/// and their `wayfinder/` namespace is not a Profile id.
///
/// An error-level diagnostic means the run did not assess everything it was
/// asked to, so the gate cannot pass.
enum DiagnosticCode {
  configMissing(
    'config-missing',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'No configuration selects a Profile for the bundle.',
  ),
  configInvalid(
    'config-invalid',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'The configuration that selects a Profile cannot be read.',
  ),
  bundleUnbound(
    'bundle-unbound',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'The configuration does not bind the bundle to a Profile.',
  ),
  profileUnresolved(
    'profile-unresolved',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'The configured Profile source is not resolved locally.',
  ),
  profileInvalid(
    'profile-invalid',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'A Profile package in the selected chain is malformed.',
  ),
  profileUnsupported(
    'profile-unsupported',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'This wayfinder cannot read a Profile package in the selected chain.',
  ),
  profileTimeout(
    'profile-timeout',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'A Profile package in the selected chain did not finish loading within '
        'the time the engine allows.',
  ),
  profileComposition(
    'profile-composition',
    DiagnosticLevel.error,
    DiagnosticChannel.configuration,
    'The selected Profile chain and project additions do not compose.',
  ),
  profileSkillStale(
    'profile-skill-stale',
    DiagnosticLevel.warning,
    DiagnosticChannel.configuration,
    "A project's copy of a Profile skill is not the locked revision.",
  ),
  projectType(
    'project-type',
    DiagnosticLevel.note,
    DiagnosticChannel.configuration,
    'The project configuration adds a type to the Profile types.',
  ),
  linkGraphUnavailable(
    'link-graph-unavailable',
    DiagnosticLevel.error,
    DiagnosticChannel.execution,
    'The OKF link graph could not be built, so link rules were not assessed.',
  ),
  fixFailed(
    'fix-failed',
    DiagnosticLevel.error,
    DiagnosticChannel.execution,
    'A generated file could not be written.',
  ),
  fixNotApplied(
    'fix-not-applied',
    DiagnosticLevel.warning,
    DiagnosticChannel.execution,
    'The requested fix did not run.',
  ),
  internalError(
    'internal-error',
    DiagnosticLevel.error,
    DiagnosticChannel.execution,
    'wayfinder stopped on an unexpected error.',
  );

  const DiagnosticCode(this.slug, this.level, this.channel, this.description);

  final String slug;
  final DiagnosticLevel level;
  final DiagnosticChannel channel;

  /// What the code means in general; SARIF's notification descriptor text.
  final String description;

  String get id => 'wayfinder/$slug';
}

/// What fixes a failure, as data for a host to word in its own terms. The
/// engine's messages name no command (ADR-0018): the `wayfinder` command
/// adds what to run, and another host says what it offers instead.
enum DiagnosticRemedy {
  /// Resolve the project's Profiles again: write `wayfinder.lock` from
  /// `wayfinder.json` and install the locked Profile skills, fetching what
  /// the Profile cache lacks. On the command line, `wayfinder get`.
  resolveProfiles('resolve-profiles'),

  /// Resolve the project's Profiles again, which reads the locked commit
  /// from the source's mirror already in the Profile cache, so it fetches
  /// nothing while that mirror holds the commit. On the command line,
  /// `wayfinder get`.
  resolveProfilesFromMirror('resolve-profiles-from-mirror'),

  /// Select new revisions deliberately: move each configured ref to the
  /// commit it names now and lock that. On the command line,
  /// `wayfinder upgrade`.
  upgradeProfiles('upgrade-profiles');

  const DiagnosticRemedy(this.wireValue);

  /// A stable value for a host that records the remedy.
  final String wireValue;
}

/// Why resolving would change `wayfinder.lock`: the kind of the project
/// library's `ProfileLockChange`, and [EngineDiagnostic.lockChange] for a
/// diagnostic that reports one.
enum ProfileLockChangeKind {
  /// There is no `wayfinder.lock`, or it cannot be read or parsed.
  lockMissing('lock-missing'),

  /// `wayfinder.json` changed after the lock was written: the lock's
  /// configuration hash no longer matches it.
  configurationChanged('configuration-changed'),

  /// The lock holds no complete chain for the change's binding
  /// (`ProfileLockChange.profile`).
  chainMissing('chain-missing'),

  /// The lock records another source, ref or path for the change's binding
  /// (`ProfileLockChange.profile`) than `wayfinder.json` names.
  sourceChanged('source-changed'),

  /// Each of the change's packages (`ProfileLockChange.packages`) declares
  /// another release or parent than the lock records, or a parent the lock
  /// pins no commit of.
  packageChanged('package-changed'),

  /// The lock holds the change's packages (`ProfileLockChange.packages`),
  /// which no configured chain reaches.
  packagesUnreached('packages-unreached');

  const ProfileLockChangeKind(this.wireValue);

  /// The stable value `ProfileLockChange.toJson` reports.
  final String wireValue;
}

sealed class DiagnosticLocation {
  const DiagnosticLocation();

  /// The path reports print: bundle-relative, or the project file as given.
  String get path;
}

/// The project configuration file. [path] is what reports print: the
/// configured path as the caller spelled it, or the file's basename when it
/// was discovered. [file] is the file actually read.
final class ProjectFileLocation extends DiagnosticLocation {
  const ProjectFileLocation({required this.path, required this.file});

  @override
  final String path;
  final String file;
}

/// A bundle-relative path.
final class BundleLocation extends DiagnosticLocation {
  const BundleLocation(this.path);

  @override
  final String path;
}

final class EngineDiagnostic {
  const EngineDiagnostic(
    this.code,
    this.message, {
    this.location,
    this.remedy,
    this.lockChange,
  });

  final DiagnosticCode code;

  /// What happened, naming no command.
  final String message;
  final DiagnosticLocation? location;

  /// What fixes it, when the engine knows: a host words it, as the
  /// `wayfinder` command adds `Run wayfinder get.` for
  /// [DiagnosticRemedy.resolveProfiles]. Not part of the result's JSON, text
  /// or SARIF, whose `message` is the host's to word
  /// (`ProfileValidationResult.withDiagnosticMessages`).
  final DiagnosticRemedy? remedy;

  /// Why `wayfinder.lock` would change, for a diagnostic that reports a
  /// missing or stale lock, so a host can word that cause in its own terms,
  /// as the `wayfinder` command says the configuration changed after
  /// `wayfinder get`. Like [remedy], not part of the result's JSON, text or
  /// SARIF.
  final ProfileLockChangeKind? lockChange;

  String get id => code.id;
  DiagnosticLevel get level => code.level;
  bool get isError => code.level == DiagnosticLevel.error;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'level': level.name,
    'message': message,
    if (location case final location?) 'location': {'path': location.path},
  };

  String toText() => switch (location) {
    null => '${level.name} $id: $message',
    final location => '${location.path}: ${level.name} $id: $message',
  };
}
