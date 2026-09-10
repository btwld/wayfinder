import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

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
  ModelDownloadManager? legacyDownloads,
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
          namespace: 'wayfinder-embeddings',
        );
    final source = ModelSource.url(Uri.parse(model.url));
    final legacy =
        legacyDownloads ??
        (downloads == null
            // ignore: prefer_const_constructors
            ? DefaultModelDownloadManager.sharedCache(
                namespace: 'concepta-knowledge',
              )
            : null);
    ModelCacheEntry? entry;
    // Check both caches without network access before starting a new download.
    // Keep the legacy cache intact for old binaries and offline installations.
    for (final cache in [manager, ?legacy]) {
      try {
        entry = await cache.ensureModel(
          source,
          options: ModelLoadOptions(
            sha256: model.sha256,
            cachePolicy: ModelCachePolicy.cacheOnly,
          ),
        );
        break;
      } on LlamaStateException {
        // The pinned native manager reports a cache miss with this exception.
      }
    }
    entry ??= await manager.ensureModel(
      source,
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
