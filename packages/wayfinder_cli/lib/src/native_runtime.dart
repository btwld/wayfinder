import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile, localEmbeddingModel;

// The native resources only the installed command owns: ObjectBox's library
// and the local model, located next to the executable in a native bundle or in
// the wayfinder_embeddings package during development. The retrieval library
// never looks for them itself (ADR-0018).

/// The knowledge store `wayfinder` uses: Wayfinder's data directory, the
/// local model, and ObjectBox loaded from the bundle. The MCP server
/// [retainEncoder]s across calls; one-shot commands do not.
WayfinderKnowledgeStore openKnowledgeStore({bool retainEncoder = false}) =>
    WayfinderKnowledgeStore(
      dataDirectory: WayfinderDataDirectory.resolve(),
      encoder: const _InstalledModel(),
      retainEncoder: retainEncoder,
      loadObjectBox: loadObjectBox,
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

var _objectBoxLoaded = false;

/// Loads ObjectBox's native library before ObjectBox's own discovery runs,
/// which can print to stdout and corrupt an MCP transport. Does nothing once
/// the process provides ObjectBox's symbols.
Future<void> loadObjectBox() async {
  if (_objectBoxLoaded) return;
  // DynamicLibrary.process is unavailable on Windows.
  if (!Platform.isWindows) {
    try {
      if (DynamicLibrary.process().providesSymbol('obx_version')) {
        _objectBoxLoaded = true;
        return;
      }
    } on Object {
      // Locate the library below.
    }
  }
  final name = Platform.isWindows
      ? 'objectbox.dll'
      : Platform.isMacOS
      ? 'libobjectbox.dylib'
      : 'libobjectbox.so';
  var library = File(
    p.join(_installation.path, Platform.isWindows ? 'bin' : 'lib', name),
  );
  if (!library.existsSync()) {
    final package = await _embeddingsPackage();
    if (package != null) library = File.fromUri(package.resolve(name));
  }
  if (!library.existsSync()) {
    throw const WayfinderException(
      'objectbox-unavailable',
      'The ObjectBox native library is missing. Reinstall the complete '
          'Wayfinder bundle; for source development run melos run '
          'objectbox:install.',
    );
  }
  try {
    DynamicLibrary.open(library.absolute.path);
  } on ArgumentError {
    throw const WayfinderException(
      'objectbox-unavailable',
      'The ObjectBox native library cannot load on this platform. '
          'Reinstall the matching Wayfinder bundle.',
    );
  }
  _objectBoxLoaded = true;
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
