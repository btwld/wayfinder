import 'dart:convert';
import 'dart:io';

import 'src/model_preparation.dart';

/// Measures an empty task-owned model cache, then verified offline reuse.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('OUTPUT_JSON');
  final directory = await Directory.systemTemp.createTemp(
    'model_prepare_benchmark',
  );
  try {
    final cache = Directory('${directory.path}/cache');
    final watch = Stopwatch()..start();
    final model = await prepareEmbeddingModel(
      output: Directory('${directory.path}/models'),
      cacheDirectory: cache,
      legacyDownloads: const [],
    );
    final firstMs = watch.elapsedMicroseconds / 1000;
    watch.reset();
    await prepareEmbeddingModel(
      output: Directory('${directory.path}/models'),
      cacheDirectory: cache,
      legacyDownloads: const [],
      offline: true,
    );
    final cachedMs = watch.elapsedMicroseconds / 1000;
    await File(args.single).writeAsString(
      '${jsonEncode({'emptyCachePreparationMs': firstMs, 'verifiedOfflinePreparationMs': cachedMs, 'modelPayloadBytes': await model.length(), 'cachedDownloadBytes': 0, 'note': 'Payload bytes, not HTTP wire bytes; first includes download/hash/staging; SDK and Dart packages already installed'})}\n',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
