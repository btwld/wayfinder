import 'dart:io';

import 'package:wayfinder/project.dart' show WayfinderException;

import '../embedding/base_embedder.dart';
import '../embedding/embedding_model_spec.dart';
import '../embedding/llama_embedder.dart';

/// The identity of an encoder: the [BaseEmbedder.modelName] and
/// [BaseEmbedder.sourceName] it reports.
typedef WayfinderEncoderIdentity = ({String model, String source});

/// An open encoder: its embedder, the tokenizer that counts an input's
/// tokens, and the most tokens one input may have.
///
/// A `WayfinderKnowledgeStore` disposes the [embedder] of every encoder its
/// provider opens.
final class WayfinderEncoder {
  WayfinderEncoder(this.embedder, this.countTokens, this.maxTokens);

  final BaseEmbedder embedder;
  final Future<int> Function(String) countTokens;
  final int maxTokens;
}

/// Where a `WayfinderKnowledgeStore` gets its encoder.
///
/// The host supplies it, so the store never locates a model, loads native
/// code for one or downloads anything (ADR-0018).
abstract interface class WayfinderEncoderProvider {
  /// What every encoder [open] returns reports, known without opening one.
  ///
  /// It selects the index directory and decides whether a saved index is
  /// current, so a current index needs no model. An opened encoder that
  /// reports another identity is refused with `model-invalid`.
  WayfinderEncoderIdentity get identity;

  /// Opens a new encoder, which the caller disposes. Throws a
  /// [WayfinderException] with code `model-missing` or `model-invalid` when
  /// the model cannot be used.
  Future<WayfinderEncoder> open();
}

/// A local GGUF model file the host located, opened with [LlamaEmbedder].
///
/// [open] verifies the file's size and SHA-256 against [spec] before it
/// loads the model, so a host need not verify it first; [verify] checks the
/// same without loading. Both report a file that is missing or unreadable
/// as `model-missing` and other bytes as `model-invalid`, and what fixes
/// either is [EmbeddingModelRemedy.provideModel]: a host keys its wording
/// on the code.
final class LocalModelEncoderProvider implements WayfinderEncoderProvider {
  LocalModelEncoderProvider({
    required this.modelFile,
    this.spec = localEmbeddingModel,
  });

  /// The identity of a provider for [spec], known without a model file.
  static WayfinderEncoderIdentity identityFor(EmbeddingModelSpec spec) =>
      (model: LlamaEmbedder.modelNameFor(spec), source: LlamaEmbedder.source);

  final File modelFile;
  final EmbeddingModelSpec spec;

  @override
  WayfinderEncoderIdentity get identity => identityFor(spec);

  /// Checks [modelFile]'s size and SHA-256 without loading it, with the
  /// failures [open] reports.
  Future<void> verify() => _guard(() => spec.verify(modelFile));

  @override
  Future<WayfinderEncoder> open() => _guard(() async {
    final embedder = await LlamaEmbedder.open(
      modelFile: modelFile,
      model: spec,
    );
    return WayfinderEncoder(embedder, embedder.countTokens, spec.maxTokens);
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FileSystemException {
      throw WayfinderException(
        'model-missing',
        'The local embedding model is missing or unreadable '
            '(${modelFile.path}).',
      );
    } on FormatException {
      throw WayfinderException(
        'model-invalid',
        'The local embedding model failed verification (${modelFile.path}).',
      );
    }
  }
}
