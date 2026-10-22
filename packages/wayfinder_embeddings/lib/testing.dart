/// Test support for hosts of `knowledge_store.dart`: a deterministic encoder
/// that exercises indexing, storage and search without a model.
///
/// Its vectors check mechanisms only; they are not a retrieval baseline
/// (ADR-0017). Import this library from tests, never from shipping code.
///
/// ```dart
/// final encoder = DeterministicEncoderProvider();
/// final store = WayfinderKnowledgeStore(
///   dataDirectory: Directory(temp),
///   encoder: encoder,
/// );
/// await store.index(bundle);
/// final result = await store.search([bundle], 'password recovery');
/// ```
library;

export 'src/testing/deterministic_encoder.dart';
