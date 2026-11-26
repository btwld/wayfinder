/// Shared validation, identity keys and cosine scoring for storage drivers.
library;

export 'src/storage/embedding_key.dart' show embeddingIdentityKey;
export 'src/storage/vector_validation.dart'
    show
        validateEmbeddingIdentityFilter,
        validateQueryVector,
        validateReplacementIds;
export 'src/util/checks.dart' show checkNotBlank;
export 'src/util/similarity.dart' show cosineSimilarity;
