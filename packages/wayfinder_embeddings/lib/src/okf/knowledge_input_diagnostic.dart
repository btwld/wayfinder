/// A successful embedding-input recovery, aggregated by source and code.
class KnowledgeInputDiagnostic {
  const KnowledgeInputDiagnostic({
    required this.code,
    required this.sourcePath,
    required this.lineStart,
    required this.lineEnd,
    required this.affectedChunks,
  });

  final String code;
  final String sourcePath;
  final int lineStart;
  final int lineEnd;
  final int affectedChunks;

  Map<String, Object?> toJson() => {
    'code': code,
    'sourcePath': sourcePath,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'affectedChunks': affectedChunks,
  };
}
