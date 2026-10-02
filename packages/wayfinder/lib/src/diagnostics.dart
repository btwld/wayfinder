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
  const EngineDiagnostic(this.code, this.message, {this.location});

  final DiagnosticCode code;
  final String message;
  final DiagnosticLocation? location;

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
