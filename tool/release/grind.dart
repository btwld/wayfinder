import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> arguments) {
  // cli_pkg reads pubspec.yaml from the current directory.  The published
  // package lives at packages/okf_profile inside a Dart workspace, so we
  // temporarily point there for cli_pkg initialisation, then restore the
  // repository root before grinder executes any task.
  final repoRoot = Directory.current.absolute.path;
  Directory.current = 'packages/okf_profile';

  // Force the top-level lazy `version` (and the `pubspec` it depends on)
  // to initialise NOW, while cwd points to the package.
  pkg.version; // ignore: unnecessary_statements

  Directory.current = repoRoot;

  pkg.executables.value = <String, String>{
    'okfp': 'packages/okf_profile/bin/okfp.dart',
  };
  pkg.useExe.value = (_) => true;
  pkg.addStandaloneTasks();
  grind(arguments);
}

@Task('Build and stage the current platform executable.')
@Depends('pkg-compile-native')
void okfpBuildBinary() {
  final asset = File(_requiredEnvironment('ASSET'));
  asset.parent.createSync(recursive: true);
  File('build/okfp.native').copySync(asset.path);

  if (!Platform.isWindows) {
    run('chmod', arguments: <String>['a+x', asset.path]);
  }
}

@Task('Publish an immutable GitHub release from staged assets.')
Future<void> okfpDeployGithub() async {
  await runAsync(
    'bash',
    arguments: <String>[
      'tool/ci/publish-release.sh',
      _requiredEnvironment('TAG'),
      _requiredEnvironment('DISTRIBUTION'),
    ],
  );
}

@Task('Point the Homebrew formula at the published pub.dev archive.')
Future<void> okfpDeployHomebrew() async {
  await runAsync(
    'bash',
    arguments: <String>[
      'tool/ci/bump-homebrew.sh',
      _requiredEnvironment('TAG'),
    ],
  );
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

@Task('Publish the package using the configured pub.dev credentials.')
Future<void> okfpDeployPub() async {
  await runAsync(
    'dart',
    arguments: const <String>[
      'pub',
      '-C',
      'packages/okf_profile',
      'publish',
      '--force',
      // The `verify` job already ran `dart pub publish --dry-run` at this
      // commit without a credential. Resolving again here would authenticate
      // the public version-listing and advisory reads, which pub.dev answers
      // with HTTP 403: https://github.com/dart-lang/pub-dev/issues/9576.
      // pub.dev still validates the archive server-side on upload. Drop this
      // once that issue is fixed.
      '--skip-validation',
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
