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
          '${error.message} Reinstall the complete Wayfinder bundle; for '
              'source development run melos run wayfinder_embeddings:prepare.',
        'model-invalid' =>
          '${error.message} Reinstall the complete Wayfinder bundle.',
        'resolution-stale' => '${error.message} Run wayfinder get again.',
        _ => error.message,
      },
    };

/// The message the command and the MCP server report for [diagnostic]: the
/// engine's sentence, plus what to run for its remedy.
String commandDiagnosticMessage(EngineDiagnostic diagnostic) =>
    switch (diagnostic.remedy) {
      final remedy? => '${diagnostic.message} ${_run(remedy)}',
      null => diagnostic.message,
    };

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
