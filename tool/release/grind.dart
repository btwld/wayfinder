import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> arguments) {
  // cli_pkg reads pubspec.yaml from the current directory.  The published
  // package lives at packages/wayfinder_cli inside a Dart workspace, so we
  // temporarily point there for cli_pkg initialisation, then restore the
  // repository root before grinder executes any task.
  final repoRoot = Directory.current.absolute.path;
  Directory.current = 'packages/wayfinder_cli';

  // Force the top-level lazy `version` (and the `pubspec` it depends on)
  // to initialise NOW, while cwd points to the package.
  pkg.version; // ignore: unnecessary_statements

  Directory.current = repoRoot;

  pkg.executables.value = <String, String>{
    'wayfinder': 'packages/wayfinder_cli/bin/wayfinder.dart',
  };
  pkg.useExe.value = (_) => true;
  pkg.addStandaloneTasks();
  grind(arguments);
}

// cli_pkg's default standalone archive omits Wayfinder's native assets and
// its release task hardcodes bare version tags. Keep the tested complete bundle
// and package-prefixed tags in these project deployment tasks.
@Task('Publish the verified complete Wayfinder runtime to GitHub.')
Future<void> wayfinderDeployGithub() async {
  await runAsync(
    'bash',
    arguments: <String>[
      'tool/ci/publish-wayfinder.sh',
      _requiredEnvironment('DISTRIBUTION'),
    ],
  );
}

@Task('Update the Wayfinder formula in Concepta’s existing Homebrew tap.')
Future<void> wayfinderDeployHomebrew() async {
  await runAsync(
    'python3',
    arguments: <String>[
      'tool/ci/update-wayfinder-homebrew.py',
      _requiredEnvironment('DISTRIBUTION'),
    ],
  );
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    fail('$name must be set.');
  }
  return value;
}
