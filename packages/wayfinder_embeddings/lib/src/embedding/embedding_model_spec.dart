import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

/// Pinned artifact and preprocessing contract for a local embedding model.
class EmbeddingModelSpec {
  const EmbeddingModelSpec({
    required this.id,
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.dimensions,
    required this.maxTokens,
    required this.queryPrefix,
    required this.license,
  });

  final String id;
  final String url;
  final String sha256;
  final int bytes;
  final int dimensions;
  final int maxTokens;
  final String queryPrefix;
  final String license;

  /// Stable staging name; the manifest identifies the exact artifact.
  String get fileName => 'embedding.gguf';

  /// Verifies bytes before loading native code or staging a build asset.
  ///
  /// Throws [EmbeddingModelMissingException], a [FileSystemException], when
  /// [file] does not exist, and [EmbeddingModelMismatchException], a
  /// [FormatException], when its size or SHA-256 is not this model's. Their
  /// messages say what happened and name no command; their `remedy` says
  /// what fixes it, for a host to word.
  Future<void> verify(File file) async {
    if (!await file.exists()) {
      throw EmbeddingModelMissingException(file.path);
    }
    if (await file.length() != bytes ||
        (await crypto.sha256.bind(file.openRead()).first).toString() !=
            sha256) {
      throw EmbeddingModelMismatchException(file.path);
    }
  }

  /// Everything about this artifact that changes the vectors it produces.
  ///
  /// Provenance ([url] and [license]) is deliberately excluded so that moving
  /// to another mirror of the same verified bytes does not invalidate stored
  /// vectors. [sha256] already pins the bytes themselves.
  Map<String, Object> get identityMap => {
    'id': id,
    'sha256': sha256,
    'bytes': bytes,
    'dimensions': dimensions,
    'maxTokens': maxTokens,
    'queryPrefix': queryPrefix,
  };

  /// Full record for manifests and run provenance, including where the bytes
  /// came from. Use [identityMap] for anything that keys stored vectors.
  Map<String, Object> toMap() => {
    'id': id,
    'url': url,
    'sha256': sha256,
    'bytes': bytes,
    'dimensions': dimensions,
    'maxTokens': maxTokens,
    'queryPrefix': queryPrefix,
    'license': license,
  };
}

/// What fixes a model [EmbeddingModelSpec.verify] refuses, as data for a
/// host to word: the library's messages name no command (ADR-0018).
enum EmbeddingModelRemedy {
  /// Put a verified copy of the pinned model where the host looks for it:
  /// download it with `EmbeddingModelCache.provision`, or name a copy that
  /// passes [EmbeddingModelSpec.verify]. The `wayfinder` command says to
  /// reinstall its complete bundle, and in a source checkout to prepare the
  /// model with Melos.
  provideModel('provide-model');

  const EmbeddingModelRemedy(this.wireValue);

  /// A stable value for a host that records the remedy.
  final String wireValue;
}

/// [EmbeddingModelSpec.verify] found no model file at [path]. It is a
/// [FileSystemException], so code that catches one still does.
final class EmbeddingModelMissingException extends FileSystemException {
  const EmbeddingModelMissingException(String path)
    : super('Embedding model is missing.', path);

  /// What fixes it.
  EmbeddingModelRemedy get remedy => EmbeddingModelRemedy.provideModel;
}

/// [EmbeddingModelSpec.verify] found a model file at [path] whose size or
/// SHA-256 is not the pinned model's. It is a [FormatException], so code
/// that catches one still does.
final class EmbeddingModelMismatchException extends FormatException {
  EmbeddingModelMismatchException(this.path)
    : super('Embedding model size or SHA-256 mismatch: $path');

  /// The file that failed verification.
  final String path;

  /// What fixes it.
  EmbeddingModelRemedy get remedy => EmbeddingModelRemedy.provideModel;
}

/// Arctic Embed XS Q8_0, using CLS pooling and normalized retrieval vectors.
///
/// The GGUF is a community conversion of Snowflake's Apache-2.0 model.
const localEmbeddingModel = EmbeddingModelSpec(
  id: 'arctic-embed-xs-q8_0',
  url:
      'https://huggingface.co/mradermacher/snowflake-arctic-embed-xs-GGUF/'
      'resolve/143419f28857ed7f3b1afd13713f3b3955231338/'
      'snowflake-arctic-embed-xs.Q8_0.gguf',
  sha256: 'a2fe17db11616959ab2235a7727bc7d080becfe77b6ab16671b25866da8ea582',
  bytes: 25279840,
  dimensions: 384,
  maxTokens: 512,
  queryPrefix: 'Represent this sentence for searching relevant passages: ',
  license: 'Apache-2.0',
);

/// The model file an override in [environment] names, else the packaged one
/// in an [installation]'s `models/`, else `models/` under the current
/// directory during development.
///
/// `WAYFINDER_EMBEDDING_MODEL` takes precedence over discovery, including an
/// invalid path; the legacy `KNOWLEDGE_EMBEDDING_MODEL` remains supported.
/// [installation] is the root of an installed bundle, the parent of its
/// `bin/`. This library never derives it from the running executable: a
/// native entry point that ships the model beside itself passes it.
File defaultEmbeddingModelFile({
  Map<String, String>? environment,
  Directory? installation,
}) {
  final env = environment ?? Platform.environment;
  final override =
      env['WAYFINDER_EMBEDDING_MODEL'] ?? env['KNOWLEDGE_EMBEDDING_MODEL'];
  if (override != null) {
    if (override.trim().isEmpty) {
      throw const FileSystemException('The embedding model override is empty.');
    }
    return File(override);
  }
  if (installation != null) {
    final bundled = File(
      p.join(installation.path, 'models', localEmbeddingModel.fileName),
    );
    if (bundled.existsSync()) return bundled;
  }
  return File(p.join('models', localEmbeddingModel.fileName));
}
