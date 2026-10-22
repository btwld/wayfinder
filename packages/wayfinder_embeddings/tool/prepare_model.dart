import 'dart:io';

import 'package:args/args.dart';
import 'package:wayfinder_embeddings/model_cache.dart';

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
    var reported = -1;
    final model = await prepareEmbeddingModel(
      output: Directory(options.option('output')!),
      offline: options.flag('offline'),
      onProgress: (step) {
        switch (step) {
          case ModelDownloading(:final fraction, :final totalBytes):
            final tenths = (fraction * 10).floor();
            if (tenths > reported) {
              reported = tenths;
              stdout.writeln(
                'Downloading the embedding model: ${tenths * 10}% of '
                '$totalBytes bytes',
              );
            }
          case ModelVerifying():
            stdout.writeln('Verifying the downloaded embedding model');
          case ModelProvisioned(:final file):
            stdout.writeln('Cached embedding model: ${file.path}');
        }
      },
    );
    stdout.writeln('Verified embedding model: ${model.path}');
  } catch (error) {
    stderr.writeln('Model preparation failed: $error');
    exitCode = 1;
  }
}
