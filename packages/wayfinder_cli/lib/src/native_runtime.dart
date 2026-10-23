import 'dart:io';
import 'dart:isolate';

import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/model_cache.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile;

// The native resource only the installed command owns: the local model,
// located next to the executable in a native bundle, in the
// wayfinder_embeddings package during development, or in the model cache a
// host such as an application installed in the data directory. The
// retrieval library never looks for it itself (ADR-0018).

/// The knowledge store `wayfinder` uses: Wayfinder's data directory and the
/// local model. The MCP server [retainEncoder]s across calls; one-shot
/// commands do not.
WayfinderKnowledgeStore openKnowledgeStore({bool retainEncoder = false}) =>
    WayfinderKnowledgeStore(
      dataDirectory: WayfinderDataDirectory.resolve(),
      encoder: const _InstalledModel(),
      retainEncoder: retainEncoder,
    );

/// Fails with `model-missing` or `model-invalid` when
/// `WAYFINDER_EMBEDDING_MODEL` (or the legacy `KNOWLEDGE_EMBEDDING_MODEL`)
/// names a file that is not the verified model. Indexing checks it first,
/// so an invalid explicit setting fails even when the saved index is
/// current and the model would not be opened.
Future<void> verifyModelOverride() async {
  final environment = Platform.environment;
  if (!environment.containsKey('WAYFINDER_EMBEDDING_MODEL') &&
      !environment.containsKey('KNOWLEDGE_EMBEDDING_MODEL')) {
    return;
  }
  await LocalModelEncoderProvider(modelFile: await _modelFile()).verify();
}

/// The root of an installed native bundle: the parent of the executable's
/// `bin/`.
Directory get _installation => File(Platform.resolvedExecutable).parent.parent;

/// `wayfinder_embeddings`' library directory, during source development.
Future<Uri?> _embeddingsPackage() => Isolate.resolvePackageUri(
  Uri.parse('package:wayfinder_embeddings/wayfinder_embeddings.dart'),
);

/// The model [locateModelFile] finds for this process.
Future<File> _modelFile() => locateModelFile(
  environment: Platform.environment,
  installation: _installation,
  embeddingsPackage: _embeddingsPackage,
);

/// The model file the command uses, in this order:
///
/// 1. the file `WAYFINDER_EMBEDDING_MODEL` (or the legacy
///    `KNOWLEDGE_EMBEDDING_MODEL`) in [environment] names, even when it is
///    missing or invalid;
/// 2. `models/` in the [installation], the bundle the executable belongs to;
/// 3. `models/` under the current directory;
/// 4. the one `melos run wayfinder_embeddings:prepare` downloads into the
///    `wayfinder_embeddings` package, during source development;
/// 5. the model `EmbeddingModelCache.provision` installed in the data
///    directory ([WayfinderDataDirectory.resolve] of [environment]), only
///    when it passes the cache's own size and SHA-256 check.
///
/// The first of 2 to 4 that exists is returned; the encoder verifies it
/// before loading it. When none exists and the cache holds no verified
/// model, the path of 4 is returned during source development and that of
/// 3 otherwise, so the failure names it.
Future<File> locateModelFile({
  required Map<String, String> environment,
  Directory? installation,
  Future<Uri?> Function()? embeddingsPackage,
  EmbeddingModelSpec spec = localEmbeddingModel,
}) async {
  final File model;
  try {
    model = defaultEmbeddingModelFile(
      environment: environment,
      installation: installation,
    );
  } on FileSystemException catch (error) {
    throw WayfinderException(
      'model-missing',
      'The local embedding model is missing or unreadable (${error.message}).',
    );
  }
  if (await model.exists() ||
      environment.containsKey('WAYFINDER_EMBEDDING_MODEL') ||
      environment.containsKey('KNOWLEDGE_EMBEDDING_MODEL')) {
    return model;
  }
  final package = await embeddingsPackage?.call();
  final missing = package == null
      ? model
      : File.fromUri(package.resolve('../models/${spec.fileName}'));
  if (package != null && await missing.exists()) return missing;
  final Directory dataDirectory;
  try {
    dataDirectory = WayfinderDataDirectory.resolve(environment: environment);
  } on WayfinderException {
    return missing;
  }
  final cached = await EmbeddingModelCache(
    dataDirectory: dataDirectory,
    spec: spec,
  ).locate();
  return cached ?? missing;
}

/// The pinned local model wherever [_modelFile] finds it, located when an
/// encoder is opened, so commands that never encode need no model.
final class _InstalledModel implements WayfinderEncoderProvider {
  const _InstalledModel();

  @override
  WayfinderEncoderIdentity get identity =>
      LocalModelEncoderProvider.identityFor(localEmbeddingModel);

  @override
  Future<WayfinderEncoder> open() async =>
      LocalModelEncoderProvider(modelFile: await _modelFile()).open();
}
