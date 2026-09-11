import 'package:wayfinder_embeddings/okf_knowledge.dart';

/// The shared CLI/MCP representation preserves original citations and metadata.
Map<String, Object?> searchOutput(KnowledgeSearchResponse result) => {
  'context': [
    for (final hit in result.context)
      {
        'chunk': hit.result.chunk.toMap(),
        'similarity': hit.result.similarity,
        'reason': hit.reason,
        if (hit.viaPath != null) 'viaPath': hit.viaPath,
      },
  ],
  'matches': [
    for (final hit in result.matches)
      {'chunk': hit.chunk.toMap(), 'similarity': hit.similarity},
  ],
  'notices': result.notices,
};
