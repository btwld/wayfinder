import 'package:wayfinder/project.dart';

/// The message the command and the MCP server report for [error]: the
/// library's sentence, plus what to run about it, which the libraries leave
/// to their host. [indexing] says the failing operation was an index.
String commandMessage(WayfinderException error, {bool indexing = false}) =>
    switch (error.code) {
      'index-missing' ||
      'index-stale' ||
      'index-incompatible' => '${error.message} Run wayfinder index <bundle>.',
      'bundle-changed' =>
        '${error.message} Run wayfinder index '
            '${indexing ? 'again' : '<bundle>'}.',
      'model-missing' =>
        '${error.message} Reinstall the complete Wayfinder bundle; for '
            'source development run melos run wayfinder_embeddings:prepare.',
      'model-invalid' =>
        '${error.message} Reinstall the complete Wayfinder bundle.',
      _ => error.message,
    };
