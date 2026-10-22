import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/benchmark_models.dart';
import 'src/model_preparation.dart';

/// Prepares experimental models separately from the application's model asset.
///
/// Each model downloads straight into its own directory under `--output`, so
/// benchmark weights stay out of the Wayfinder data directory that
/// applications and `prepare_model.dart` share.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('output', mandatory: true)
    ..addFlag('offline', negatable: false);
  final options = parser.parse(args);
  if (options.rest.isNotEmpty || options.option('output')!.trim().isEmpty) {
    throw ArgumentError('Use --output=DIR [--offline].');
  }
  for (final model in benchmarkModels.values) {
    final watch = Stopwatch()..start();
    final output = Directory(p.join(options.option('output')!, model.id));
    final file = await prepareEmbeddingModel(
      output: output,
      model: model,
      cacheDirectory: output,
      offline: options.flag('offline'),
    );
    stdout.writeln(
      '${model.id}: verified ${model.bytes} bytes at ${file.path} '
      '(${watch.elapsedMilliseconds} ms)',
    );
  }
}
