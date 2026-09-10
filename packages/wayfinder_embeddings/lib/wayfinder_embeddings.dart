/// A library for chunking, embedding, and searching content.
///
/// This library provides a unified API for working with different types of content
/// (code, documents, etc.) and different embedding strategies.
library;

// Chunking
export 'src/chunking/base_chunker.dart';
export 'src/chunking/chunker_registry.dart';
// Document-specific chunkers
export 'src/chunking/documents/markdown_chunker.dart';
export 'src/chunking/documents/text_chunker.dart';
// Language-specific chunkers
export 'src/chunking/languages/dart_chunker.dart';
export 'src/chunking/languages/typescript_chunker.dart';
// Embedding
export 'src/embedding/base_embedder.dart';
export 'src/embedding/embedding_model_spec.dart';
export 'src/embedding/llama_embedder.dart';
// Ingestion
export 'src/ingestion/ingestion_pipeline.dart';
// Core models
export 'src/models/chunk.dart';
export 'src/models/chunk_metadata.dart';
export 'src/models/embedding.dart';
export 'src/models/search_result.dart';
// Search
export 'src/search/bm25_lexical_index.dart';
export 'src/search/content_searcher.dart';
export 'src/search/hybrid_content_searcher.dart';
export 'src/search/parent_child_resolver.dart';
export 'src/search/parent_child_searcher.dart';
export 'src/search/reciprocal_rank_fusion.dart';
export 'src/search/reranking_content_searcher.dart';
export 'src/search/search_options.dart';
export 'src/search/search_reranker.dart';
export 'src/search/searcher.dart';
// Storage
export 'src/storage/base_store.dart';
export 'src/storage/memory_store.dart';
export 'src/storage/objectbox_store.dart';
// Utilities
export 'src/util/content_type.dart';
