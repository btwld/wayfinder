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
  Future<void> verify(File file) async {
    if (!await file.exists()) {
      throw FileSystemException(
        'Embedding model is missing. Run melos run embeddings:prepare '
        'or provide a verified model path.',
        file.path,
      );
    }
    if (await file.length() != bytes ||
        (await crypto.sha256.bind(file.openRead()).first).toString() !=
            sha256) {
      throw FormatException(
        'Embedding model size or SHA-256 mismatch: ${file.path}',
      );
    }
  }

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

/// Uses the packaged model next to an executable, or `models/` during development.
File defaultEmbeddingModelFile() {
  final override = Platform.environment['KNOWLEDGE_EMBEDDING_MODEL'];
  if (override != null && override.trim().isNotEmpty) return File(override);
  final bundled = File(
    p.join(
      File(Platform.resolvedExecutable).parent.parent.path,
      'models',
      localEmbeddingModel.fileName,
    ),
  );
  return bundled.existsSync()
      ? bundled
      : File(p.join('models', localEmbeddingModel.fileName));
}
