/// Locate the pinned local embedding model offline, and download it only
/// when a host asks.
///
/// `EmbeddingModelCache.locate` reads files and never touches the network.
/// `EmbeddingModelCache.provision` downloads `localEmbeddingModel` into the
/// cache directory, by default `models/<id>` in the Wayfinder data directory,
/// verifies its size and SHA-256, and only then renames it into place. A
/// host calls it after the user agrees to the download its
/// `EmbeddingModelCache.target` describes.
///
/// The entry also exports the `package:wayfinder/project.dart` types its
/// API uses: `WayfinderException` for failures, `WayfinderCancellation` and
/// `WayfinderCancellationController` to stop a download, and
/// `WayfinderDataDirectory` for the default data directory. A host needs no
/// direct `wayfinder` dependency to use it.
///
/// ```dart
/// import 'package:wayfinder_embeddings/model_cache.dart';
///
/// Future<void> main() async {
///   final cache = EmbeddingModelCache();
///   var model = await cache.locate();
///   if (model == null) {
///     await for (final step in cache.provision()) {
///       switch (step) {
///         case ModelDownloading(:final fraction):
///           print('${(fraction * 100).round()}%');
///         case ModelVerifying():
///           print('Verifying');
///         case ModelProvisioned(:final file):
///           model = file;
///       }
///     }
///   }
///   print('Model: ${model!.path}');
/// }
/// ```
library;

export 'package:wayfinder/project.dart'
    show
        WayfinderCancellation,
        WayfinderCancellationController,
        WayfinderDataDirectory,
        WayfinderException;

export 'src/embedding/embedding_model_spec.dart'
    show
        EmbeddingModelMismatchException,
        EmbeddingModelMissingException,
        EmbeddingModelRemedy,
        EmbeddingModelSpec,
        localEmbeddingModel;
export 'src/embedding/model_cache.dart'
    show
        EmbeddingModelCache,
        EmbeddingModelTarget,
        ModelDownloading,
        ModelProvisionProgress,
        ModelProvisioned,
        ModelVerifying;
