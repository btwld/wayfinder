/// Saved local indexes of OKF bundles and dense search over them, for a host
/// that embeds what `wayfinder index` and `wayfinder search` do.
///
/// A `WayfinderKnowledgeStore` indexes and searches the bundles of a
/// `package:wayfinder/project.dart` project. The host owns the resources: it
/// supplies the data directory, a `WayfinderEncoderProvider` (such as a
/// `LocalModelEncoderProvider` over a model file it located) and, when it
/// has not loaded ObjectBox's native library itself, a loader for it. The
/// store never downloads, prompts, or loads native code or a model on its
/// own (ADR-0018). Keep all okf bundle I/O of a process, this store's
/// included, on one isolate.
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:wayfinder/project.dart';
/// import 'package:wayfinder_embeddings/knowledge_store.dart';
///
/// final project = await WayfinderProject.discover(Directory.current);
/// final store = WayfinderKnowledgeStore(
///   dataDirectory: WayfinderDataDirectory.resolve(),
///   encoder: LocalModelEncoderProvider(modelFile: File('embedding.gguf')),
/// );
/// try {
///   for (final bundle in project.bundles) {
///     await store.index(bundle);
///   }
///   final result = await store.search(project.bundles, 'password reset');
///   print(result.toMarkdown());
/// } finally {
///   await store.dispose();
/// }
/// ```
///
/// `package:wayfinder_embeddings/testing.dart` has a deterministic encoder
/// for tests.
library;

// What a host names to implement an encoder provider, read a citation's
// passage, choose another model, or build search results in a fake.
export 'src/embedding/base_embedder.dart' show BaseEmbedder;
export 'src/embedding/embedding_model_spec.dart'
    show EmbeddingModelSpec, localEmbeddingModel;
// The llama.cpp release the store's configuration names, which a host that
// shares indexes checks its resolved llamadart against.
export 'src/embedding/llama_embedder.dart' show wayfinderLlamaCppRuntime;
export 'src/models/chunk.dart' show Chunk;
export 'src/models/search_result.dart' show SearchResult;
export 'src/okf/knowledge_index.dart'
    show KnowledgeContextHit, KnowledgeMetadataFilter, KnowledgeSearchResponse;
export 'src/okf/knowledge_input_diagnostic.dart';
export 'src/store/encoder.dart';
export 'src/store/index_result.dart';
export 'src/store/knowledge_store.dart';
export 'src/store/project_search.dart';
export 'src/store/search_input.dart';
