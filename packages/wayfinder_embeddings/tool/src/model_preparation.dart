import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/model_cache.dart';

/// Stages the pinned model for development or an application bundle.
///
/// A verified model already in [output] needs nothing else. Otherwise the
/// model is copied from the first verified copy found without network
/// access: the [EmbeddingModelCache] in [cacheDirectory] (by default its
/// directory in the Wayfinder data directory), then the llamadart caches
/// earlier releases downloaded into ([legacyDownloads]), which keep their
/// files. Only when none has it, and not [offline], does the cache download
/// it. A copy is verified before it is renamed into [output], so a corrupt
/// or interrupted preparation never replaces a staged model. A
/// [cacheDirectory] equal to [output] downloads straight into place.
Future<File> prepareEmbeddingModel({
  required Directory output,
  bool offline = false,
  EmbeddingModelSpec model = localEmbeddingModel,
  Directory? cacheDirectory,
  http.Client? client,
  Iterable<ModelDownloadManager>? legacyDownloads,
  void Function(ModelProvisionProgress step)? onProgress,
}) async {
  await output.create(recursive: true);
  final staged = EmbeddingModelCache.inDirectory(output, spec: model);
  final target = staged.target.file;
  if (await staged.locate() == null) {
    final cache = cacheDirectory == null
        ? EmbeddingModelCache(spec: model, client: client)
        : EmbeddingModelCache.inDirectory(
            cacheDirectory,
            spec: model,
            client: client,
          );
    var source =
        await cache.locate() ??
        await _legacyCachedModel(model, legacyDownloads ?? _legacyCaches());
    if (source == null) {
      if (offline) {
        throw FileSystemException(
          'The embedding model is neither staged nor cached. '
          'Run without --offline to download it.',
          target.path,
        );
      }
      await for (final step in cache.provision()) {
        onProgress?.call(step);
        if (step is ModelProvisioned) source = step.file;
      }
    }
    if (!p.equals(source!.absolute.path, target.absolute.path)) {
      final staging = await output.createTemp('.model-');
      try {
        final copy = await source.copy(p.join(staging.path, model.fileName));
        await model.verify(copy);
        await copy.rename(target.path);
      } finally {
        await staging.delete(recursive: true);
      }
    }
  }
  await File(p.join(output.path, 'manifest.json')).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(model.toMap())}\n',
    flush: true,
  );
  return target;
}

/// The caches `prepare_model.dart` filled through llamadart before
/// `EmbeddingModelCache`: `wayfinder-embeddings` and, before that,
/// `concepta-knowledge`. Their models are read, never moved or removed; on a
/// hit llamadart only refreshes the entry's `updated_at`.
List<ModelDownloadManager> _legacyCaches() => [
  // The native conditional implementation is a non-const factory.
  // ignore: prefer_const_constructors
  DefaultModelDownloadManager.sharedCache(namespace: 'wayfinder-embeddings'),
  // ignore: prefer_const_constructors
  DefaultModelDownloadManager.sharedCache(namespace: 'concepta-knowledge'),
];

/// A verified copy of [model] in one of [caches], found without network
/// access, or null.
Future<File?> _legacyCachedModel(
  EmbeddingModelSpec model,
  Iterable<ModelDownloadManager> caches,
) async {
  final source = ModelSource.url(Uri.parse(model.url));
  for (final cache in caches) {
    try {
      final entry = await cache.ensureModel(
        source,
        options: ModelLoadOptions(
          sha256: model.sha256,
          cachePolicy: ModelCachePolicy.cacheOnly,
        ),
      );
      final file = File(entry.filePath);
      await model.verify(file);
      return file;
    } on LlamaStateException {
      // The pinned native manager reports a cache miss with this exception.
    } on FileSystemException {
      // An entry whose file is gone is a miss.
    } on FormatException {
      // So is one whose bytes no longer match the pin.
    }
  }
  return null;
}
