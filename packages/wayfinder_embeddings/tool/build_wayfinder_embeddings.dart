import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/model_preparation.dart';
import 'src/native_cli_assets.dart';
import 'src/objectbox_assets.dart';

/// Builds the existing retrieval evaluator with its verified local assets.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('output', defaultsTo: 'build/wayfinder_embeddings')
    ..addFlag('offline', negatable: false);
  try {
    final options = parser.parse(args);
    final outputPath = options.option('output')!;
    if (options.rest.isNotEmpty || outputPath.trim().isEmpty) {
      throw ArgumentError(
        'Usage: build_wayfinder_embeddings.dart [--output=DIR] [--offline]',
      );
    }
    final output = Directory(outputPath).absolute;
    final package = Directory.current.absolute;
    if (p.isWithin(output.path, package.path) ||
        p.equals(output.path, package.path)) {
      throw ArgumentError('Build output must not contain the source package.');
    }
    for (final source in ['bin', 'lib', 'tool', 'models', 'fixtures', 'test']) {
      final sourcePath = p.join(package.path, source);
      if (p.isWithin(sourcePath, output.path) ||
          p.equals(sourcePath, output.path)) {
        throw ArgumentError('Build output must not overwrite $source/.');
      }
    }
    await verifiedObjectBoxLibrary(package);
    final model = await prepareEmbeddingModel(
      output: Directory('models'),
      offline: options.flag('offline'),
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target=bin/compare_embeddings.dart',
      '--output=${output.path}',
    ], mode: ProcessStartMode.inheritStdio);
    final status = await process.exitCode;
    if (status != 0) {
      exitCode = status;
      return;
    }
    final bundle = Directory(p.join(output.path, 'bundle'));
    final bundledModels = await Directory(
      p.join(bundle.path, 'models'),
    ).create();
    await model.copy(p.join(bundledModels.path, p.basename(model.path)));
    await prepareEmbeddingModel(output: bundledModels, offline: true);
    for (final file in Directory(
      'tool/model_assets',
    ).listSync().whereType<File>()) {
      await file.copy(p.join(bundle.path, 'models', p.basename(file.path)));
    }
    await File('LICENSE').copy(p.join(bundle.path, 'LICENSE'));
    await stageObjectBoxAssets(package, bundle);
    await stageWindowsBackendAssets(bundle);
    stdout.writeln('Built retrieval bundle: ${bundle.path}');
  } catch (error) {
    stderr.writeln('Embedding build failed: $error');
    exitCode = 1;
  }
}
