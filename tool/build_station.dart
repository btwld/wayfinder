import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../packages/knowledge_embeddings/tool/src/model_preparation.dart';

/// Builds Station from the workspace root with verified model/native assets.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('offline', negatable: false)
    ..addOption('output', defaultsTo: 'build/station');
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
    final package = p.join(workspace, 'packages', 'knowledge_embeddings');
    final libraryName = Platform.isWindows
        ? 'objectbox.dll'
        : Platform.isMacOS
        ? 'libobjectbox.dylib'
        : 'libobjectbox.so';
    final library = File(p.join(package, 'lib', libraryName));
    if (!await library.exists()) {
      throw const FileSystemException(
        'Run melos run objectbox:install before building Station.',
      );
    }
    final model = await prepareEmbeddingModel(
      output: Directory(p.join(package, 'models')),
      offline: options.flag('offline'),
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      'build',
      'cli',
      '--target=packages/station/bin/station.dart',
      '--output=${output.path}',
    ], mode: ProcessStartMode.inheritStdio);
    exitCode = await process.exitCode;
    if (exitCode != 0) return;
    final bundle = p.join(output.path, 'bundle');
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
    await library.copy(
      p.join(bundle, Platform.isWindows ? 'bin' : 'lib', libraryName),
    );
    stdout.writeln('Built Station: $bundle');
  } catch (error) {
    stderr.writeln('Station build failed: $error');
    exitCode = 1;
  }
}
