import 'dart:convert';
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

/// Stages the pinned model for development or an application bundle.
///
/// Download/resume/cache ownership stays with llamadart. A verified local model
/// needs no network. A corrupt or interrupted download never replaces a staged
/// model; only a verified copy is renamed into place.
Future<File> prepareEmbeddingModel({
  required Directory output,
  bool offline = false,
  EmbeddingModelSpec model = localEmbeddingModel,
  ModelDownloadManager? downloads,
}) async {
  await output.create(recursive: true);
  final target = File(p.join(output.path, model.fileName));
  var valid = false;
  if (await target.exists()) {
    try {
      await model.verify(target);
      valid = true;
    } on FormatException {
      // Recover from a partial or stale staged file via the verified cache.
    }
  }
  if (!valid) {
    final manager =
        downloads ??
        // The native conditional implementation is a non-const factory.
        // ignore: prefer_const_constructors
        DefaultModelDownloadManager.sharedCache(
          namespace: 'concepta-knowledge',
        );
    final entry = await manager.ensureModel(
      ModelSource.url(Uri.parse(model.url)),
      options: ModelLoadOptions(
        sha256: model.sha256,
        cachePolicy: offline
            ? ModelCachePolicy.cacheOnly
            : ModelCachePolicy.preferCached,
      ),
    );
    final cached = File(entry.filePath);
    await model.verify(cached);
    final staging = await output.createTemp('.model-');
    try {
      final staged = await cached.copy(p.join(staging.path, model.fileName));
      await model.verify(staged);
      await staged.rename(target.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }
  await File(p.join(output.path, 'manifest.json')).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(model.toMap())}\n',
    flush: true,
  );
  return target;
}
