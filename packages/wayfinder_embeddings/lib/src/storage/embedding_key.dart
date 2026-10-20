import 'dart:convert';

/// Computes an unambiguous storage key for one chunk/source/model embedding.
String embeddingIdentityKey({
  required String chunkId,
  required String source,
  required String modelName,
}) => jsonEncode(<String>[chunkId, source, modelName]);
