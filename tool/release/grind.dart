import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> arguments) {
  // The published package lives inside the workspace at
  // packages/okf_profile, so cli_pkg cannot infer name, version, or
  // entrypoint from the repository root pubspec.
  final pubspecContent =
      File('packages/okf_profile/pubspec.yaml').readAsStringSync();
  final versionMatch =
      RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspecContent);
  if (versionMatch == null) {
    fail('Cannot read version from packages/okf_profile/pubspec.yaml');
  }

  pkg.name.value = 'okf_profile';
  pkg.version.value = versionMatch.group(1)!;
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
