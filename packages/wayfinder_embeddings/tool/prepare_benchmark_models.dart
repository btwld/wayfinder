import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/benchmark_models.dart';
import 'src/model_preparation.dart';

/// Prepares experimental models separately from the application's model asset.
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
    final file = await prepareEmbeddingModel(
      output: Directory(p.join(options.option('output')!, model.id)),
      model: model,
      offline: options.flag('offline'),
    );
    stdout.writeln(
      '${model.id}: verified ${model.bytes} bytes at ${file.path} '
      '(${watch.elapsedMilliseconds} ms)',
    );
  }
}
