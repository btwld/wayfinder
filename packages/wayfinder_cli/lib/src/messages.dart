import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart'
    show DiagnosticRemedy, EngineDiagnostic, ProfileValidationResult;

/// The message the command and the MCP server report for [error]: the
/// library's sentence, plus what to run about it, which the libraries leave
/// to their host. [indexing] says the failing operation was an index.
String commandMessage(WayfinderException error, {bool indexing = false}) =>
    switch (error) {
      ProfileSkillDirectoriesException(:final outsideRoots)
          when outsideRoots.isNotEmpty =>
        '${error.message} Point ${outsideRoots.length == 1 ? 'it' : 'them'} '
            'inside the project and run the command again.',
      ProfileSkillDirectoriesException() =>
        '${error.message} Move it aside and run the command again to install '
            'the Profile skill there.',
      ModelLocationException(:final remedy) => '${error.message} $remedy',
      ProfileResolutionBusyException(projectRoot: final root?) =>
        'Another wayfinder get is changing $root. Retry when it finishes.',
      WayfinderProfileResolutionException(remedy: final remedy?) =>
        '${error.message} ${_run(remedy)}',
      _ => switch (error.code) {
        'index-missing' || 'index-stale' || 'index-incompatible' =>
          '${error.message} Run wayfinder index <bundle>.',
        'bundle-changed' =>
          '${error.message} Run wayfinder index '
              '${indexing ? 'again' : '<bundle>'}.',
        'model-missing' =>
          '${error.message} Point WAYFINDER_EMBEDDING_MODEL at a verified '
              'copy of the model, reinstall the complete Wayfinder bundle, or '
              'for source development run melos run '
              'wayfinder_embeddings:prepare.',
        'model-invalid' =>
          '${error.message} Point WAYFINDER_EMBEDDING_MODEL at a verified '
              'copy of the model or reinstall the complete Wayfinder bundle.',
        'resolution-stale' => '${error.message} Run wayfinder get again.',
        _ => error.message,
      },
    };

/// The message the command and the MCP server report for [diagnostic]: the
/// engine's sentence, plus what to run for its remedy. A lock that an edit
/// of `wayfinder.json` made stale keeps the command's own wording, which
/// names the command that wrote the lock.
String commandDiagnosticMessage(EngineDiagnostic diagnostic) {
  final message = switch (diagnostic.lockChange) {
    ProfileLockChangeKind.configurationChanged =>
      'Profile lock is stale: the configuration changed after wayfinder get.',
    _ => diagnostic.message,
  };
  return switch (diagnostic.remedy) {
    final remedy? => '$message ${_run(remedy)}',
    null => message,
  };
}

/// [result] as the command and the MCP server report it, with each
/// diagnostic's remedy worded as what to run.
ProfileValidationResult commandValidation(ProfileValidationResult result) =>
    result.withDiagnosticMessages(commandDiagnosticMessage);

String _run(DiagnosticRemedy remedy) => switch (remedy) {
  DiagnosticRemedy.resolveProfiles => 'Run wayfinder get.',
  DiagnosticRemedy.resolveProfilesFromMirror =>
    'Run wayfinder get; it fetches nothing while the cached source holds '
        'that commit.',
  DiagnosticRemedy.upgradeProfiles =>
    'Run wayfinder upgrade to select a new revision.',
};

/// A model the command could not locate (`model-missing`) or found only a
/// copy of that fails verification (`model-invalid`). The message lists
/// where the command looked; [remedy] is what the command says fixes it.
final class ModelLocationException extends WayfinderException {
  const ModelLocationException(
    super.code,
    super.message, {
    required this.remedy,
  });

  final String remedy;
}
