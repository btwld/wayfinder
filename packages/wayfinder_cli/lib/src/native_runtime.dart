import 'dart:io';
import 'dart:isolate';

import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile, localEmbeddingModel;

// The native resource only the installed command owns: the local model,
// located next to the executable in a native bundle or in the
// wayfinder_embeddings package during development. The retrieval library
// never looks for it itself (ADR-0018).

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

/// The model an explicit setting names, else the bundled one, else
/// `models/` under the current directory, else the one
/// `melos run wayfinder_embeddings:prepare` downloads.
Future<File> _modelFile() async {
  final environment = Platform.environment;
  final File model;
  try {
    model = defaultEmbeddingModelFile(
      environment: environment,
      installation: _installation,
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
  final package = await _embeddingsPackage();
  return package == null
      ? model
      : File.fromUri(
          package.resolve('../models/${localEmbeddingModel.fileName}'),
        );
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
