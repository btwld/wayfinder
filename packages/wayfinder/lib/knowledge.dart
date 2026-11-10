/// Portable retained knowledge values, snapshots and independently owned leases.
/// This entry point is browser-closed: no native loading, OKF implementation,
/// Flutter, filesystem or FFI imports. Use `project.dart` for filesystem loading.
/// Inventory may include files without bytes; consult each captureFailure.
/// Browsing does not validate conformance.
library;

export 'src/knowledge/captured_project.dart' hide knowledgeFileIdentity;
export 'src/knowledge/knowledge_models.dart';
export 'src/knowledge/reader.dart'
    hide knowledgeIdentifier, knowledgeRelativePath;
