/// Portable retained knowledge values, snapshots and independently owned leases.
/// This entry point is browser-closed: no native loading, OKF implementation,
/// Flutter, filesystem or FFI imports. Use `project.dart` for filesystem loading.
/// Browsing does not validate conformance.
library;

export 'src/knowledge/captured_project.dart';
export 'src/knowledge/knowledge_models.dart';
export 'src/knowledge/manifest.dart' show knowledgeManifestFingerprint;
export 'src/knowledge/reader.dart';
