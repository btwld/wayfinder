import 'dart:convert';

/// Computes an unambiguous storage key for one chunk/source/model embedding.
String embeddingIdentityKey({
  required String chunkId,
  required String source,
  required String modelName,
}) {
  return jsonEncode(<String>[chunkId, source, modelName]);
}
