/// Counts and location of a completed local indexing operation.
class StationIndexResult {
  const StationIndexResult({
    required this.bundle,
    required this.index,
    required this.embeddedChunks,
    required this.removedChunks,
    required this.writtenChunks,
    required this.elapsedMs,
  });

  final String bundle;
  final String index;
  final int embeddedChunks;
  final int removedChunks;
  final int writtenChunks;
  final int elapsedMs;

  /// Preserves the CLI/MCP JSON contract independently of internal field access.
  Map<String, Object?> toJson() => {
    'bundle': bundle,
    'index': index,
    'embeddedChunks': embeddedChunks,
    'removedChunks': removedChunks,
    'writtenChunks': writtenChunks,
    'elapsedMs': elapsedMs,
  };
}
