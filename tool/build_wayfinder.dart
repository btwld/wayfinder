import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../packages/wayfinder_embeddings/tool/src/model_preparation.dart';
import '../packages/wayfinder_embeddings/tool/src/dependency_licenses.dart';
import '../packages/wayfinder_embeddings/tool/src/native_cli_assets.dart';
import '../packages/wayfinder_embeddings/tool/src/objectbox_assets.dart';

/// Builds Wayfinder from the workspace root with verified model/native assets.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('offline', negatable: false)
    ..addOption('output', defaultsTo: 'build/wayfinder');
  try {
    final options = parser.parse(arguments);
    final output = Directory(options.option('output')!).absolute;
    final workspace = Directory.current.absolute.path;
    if (options.rest.isNotEmpty ||
        !p.isWithin(p.join(workspace, 'build'), output.path)) {
      throw ArgumentError(
        'Output must be a subdirectory of the workspace build/ directory.',
      );
    }
    final package = p.join(workspace, 'packages', 'wayfinder_embeddings');
    await verifiedObjectBoxLibrary(Directory(package));
    final model = await prepareEmbeddingModel(
      output: Directory(p.join(package, 'models')),
      offline: options.flag('offline'),
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target=packages/wayfinder_cli/bin/wayfinder.dart',
      '--output=${output.path}',
    ], mode: ProcessStartMode.inheritStdio);
    exitCode = await process.exitCode;
    if (exitCode != 0) return;
    final bundle = p.join(output.path, 'bundle');
    final validatorLicense = await Directory(
      p.join(bundle, 'licenses', 'wayfinder'),
    ).create(recursive: true);
    await File(
      p.join(workspace, 'packages', 'wayfinder', 'LICENSE'),
    ).copy(p.join(validatorLicense.path, 'LICENSE'));

    await File(
      p.join(workspace, 'packages', 'wayfinder_cli', 'LICENSE'),
    ).copy(p.join(bundle, 'LICENSE'));
    // The skill family ships with the runtime it describes, so installing or
    // updating Wayfinder installs matching skills.
    final skills = Directory(p.join(workspace, 'skills'));
    await for (final file in skills.list(recursive: true, followLinks: false)) {
      if (file is! File) continue;
      final target = File(
        p.join(bundle, 'skills', p.relative(file.path, from: skills.path)),
      );
      await target.parent.create(recursive: true);
      await file.copy(target.path);
    }
    final models = await Directory(
      p.join(bundle, 'models'),
    ).create(recursive: true);
    await model.copy(p.join(models.path, p.basename(model.path)));
    await prepareEmbeddingModel(output: models, offline: true);
    for (final file in Directory(
      p.join(package, 'tool', 'model_assets'),
    ).listSync().whereType<File>()) {
      await file.copy(p.join(models.path, p.basename(file.path)));
    }
    await stageObjectBoxAssets(Directory(package), Directory(bundle));
    await stageNativeCliAssets(Directory(package), Directory(bundle));
    await stageDependencyLicenses(Directory(bundle), [
      'wayfinder_cli',
      'wayfinder',
    ]);
    stdout.writeln('Built Wayfinder: $bundle');
  } catch (error) {
    stderr.writeln('Wayfinder build failed: $error');
    exitCode = 1;
  }
}
