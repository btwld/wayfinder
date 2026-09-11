import 'dart:io';

import 'package:args/args.dart';

import 'src/model_preparation.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('output', defaultsTo: 'models')
    ..addFlag('offline', negatable: false);
  try {
    final options = parser.parse(args);
    if (options.rest.isNotEmpty || options.option('output')!.trim().isEmpty) {
      throw ArgumentError(
        'Usage: prepare_model.dart [--output=DIR] [--offline]',
      );
    }
    final model = await prepareEmbeddingModel(
      output: Directory(options.option('output')!),
      offline: options.flag('offline'),
    );
    stdout.writeln('Verified embedding model: ${model.path}');
  } catch (error) {
    stderr.writeln('Model preparation failed: $error');
    exitCode = 1;
  }
}
