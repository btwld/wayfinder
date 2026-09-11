/// Counts and location of a completed local indexing operation.
class WayfinderIndexResult {
  const WayfinderIndexResult({
    required this.bundle,
    required this.index,
    required this.embeddedChunks,
    required this.removedChunks,
    required this.writtenChunks,
    required this.elapsedMs,
    this.current = false,
  });

  final String bundle;
  final String index;
  final int embeddedChunks;
  final int removedChunks;
  final int writtenChunks;
  final int elapsedMs;

  /// The saved index already matched the bundle; the model was not loaded.
  final bool current;

  /// Preserves the CLI/MCP JSON contract independently of internal field access.
  Map<String, Object?> toJson() => {
    'bundle': bundle,
    'index': index,
    'embeddedChunks': embeddedChunks,
    'removedChunks': removedChunks,
    'writtenChunks': writtenChunks,
    'elapsedMs': elapsedMs,
    'current': current,
  };
}
