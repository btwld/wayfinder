import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/model_cache.dart';

import 'messages.dart' show ModelLocationException;

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
///    `KNOWLEDGE_EMBEDDING_MODEL`) in [environment] names, when it exists;
///    the encoder verifies it, and nothing else is searched while it is set;
/// 2. `models/` in the [installation], the bundle the executable belongs to;
/// 3. `models/` under the current directory;
/// 4. the one `melos run wayfinder_embeddings:prepare` downloads into the
///    `wayfinder_embeddings` package, during source development;
/// 5. the model `EmbeddingModelCache.provision` installed in the data
///    directory ([WayfinderDataDirectory.resolve] of [environment]), only
///    when it passes the cache's own size and SHA-256 check.
///
/// The first of 2 to 4 that exists is returned; the encoder verifies it
/// before loading it. Throws a [ModelLocationException] when the setting
/// is empty or names no file (`model-missing`), when none of 2 to 5 holds a
/// model (`model-missing`), and when the only one found is a cached model
/// that fails its check (`model-invalid`). Its message lists every location
/// searched, in order, with absolute paths, and its remedy says what fixes
/// it.
Future<File> locateModelFile({
  required Map<String, String> environment,
  Directory? installation,
  Future<Uri?> Function()? embeddingsPackage,
  EmbeddingModelSpec spec = localEmbeddingModel,
}) async {
  final setting = [
    'WAYFINDER_EMBEDDING_MODEL',
    'KNOWLEDGE_EMBEDDING_MODEL',
  ].where(environment.containsKey).firstOrNull;
  if (setting != null) {
    final named = environment[setting]!;
    const remedy =
        'Point it at a verified copy of the model, or unset it to use the '
        'installed one.';
    if (named.trim().isEmpty) {
      throw ModelLocationException(
        'model-missing',
        '$setting is set but empty.',
        remedy: remedy,
      );
    }
    final model = File(named);
    if (!await model.exists()) {
      throw ModelLocationException(
        'model-missing',
        '$setting names ${p.normalize(p.absolute(named))}, which does not exist; no '
            'other location is searched while it is set.',
        remedy: remedy,
      );
    }
    return model;
  }
  final package = await embeddingsPackage?.call();
  final candidates = [
    if (installation != null)
      (
        File(p.join(installation.path, 'models', spec.fileName)),
        'the installed bundle',
      ),
    (File(p.join('models', spec.fileName)), 'the current directory'),
    if (package != null)
      (
        File.fromUri(package.resolve('../models/${spec.fileName}')),
        'the wayfinder_embeddings source package',
      ),
  ];
  for (final (file, _) in candidates) {
    if (await file.exists()) return file;
  }
  final searched = [
    for (final (file, where) in candidates)
      '${p.normalize(p.absolute(file.path))} ($where)',
  ];
  File? rejected;
  try {
    final cache = EmbeddingModelCache(
      dataDirectory: WayfinderDataDirectory.resolve(environment: environment),
      spec: spec,
    );
    final cached = await cache.locate();
    if (cached != null) return cached;
    final target = cache.target.file;
    if (await target.exists()) {
      rejected = target;
    } else {
      searched.add(
        '${p.normalize(p.absolute(target.path))} (the data directory)',
      );
    }
  } on WayfinderException catch (error) {
    searched.add(
      'the data directory, which cannot be located (${error.message})',
    );
  }
  if (rejected != null) {
    throw ModelLocationException(
      'model-invalid',
      'The only local embedding model found, in the data directory '
          '(${p.normalize(p.absolute(rejected.path))}), failed its size or '
          'SHA-256 check. WAYFINDER_EMBEDDING_MODEL is not set, and none of '
          'the locations searched before it holds a model, in order: '
          '${searched.join('; ')}.',
      remedy:
          'Install it into the data directory again with an application '
          'that provisions the model, or delete it and set '
          'WAYFINDER_EMBEDDING_MODEL to a verified copy of the model, '
          'reinstall the complete Wayfinder bundle, or for source development '
          'run melos run wayfinder_embeddings:prepare.',
    );
  }
  throw ModelLocationException(
    'model-missing',
    'No local embedding model was found. WAYFINDER_EMBEDDING_MODEL is not '
        'set, and none of these exists, searched in order: '
        '${searched.join('; ')}.',
    remedy:
        'Set WAYFINDER_EMBEDDING_MODEL to a verified copy of the model, '
        'reinstall the complete Wayfinder bundle, for source development run '
        'melos run wayfinder_embeddings:prepare, or install the model into '
        'the data directory with an application that provisions it.',
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
