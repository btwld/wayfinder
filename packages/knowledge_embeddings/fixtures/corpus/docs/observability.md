# Observability Hooks

Our ingestion pipeline emits structured callbacks so that CLI tooling and CI
pipelines can surface progress without parsing raw logs.

## File-Level Callbacks

Use `onFileProcessed` to capture chunk counts per file:

```dart
final processed = <String, int>{};
await pipeline.ingestFiles(
  files,
  onFileProcessed: (file, chunks) {
    processed[file.path] = chunks.length;
  },
);
```

When a file cannot be processed, the pipeline surfaces a skip reason and the
inferred content type through `onFileSkipped`.

## Duplicate Chunks

`onDuplicateChunk` fires whenever dedupe prevents a redundant write. This is
especially helpful when rerunning incremental ingests:

```dart
await pipeline.ingestFiles(
  files,
  onDuplicateChunk: (chunk) {
    print('Skipped ${chunk.id} already stored from ${chunk.sourcePath}.');
  },
);
```

## Metrics To Add

- TODO: Track per-chunker latency once ObjectBox persistence lands.
- TODO: Emit histogram buckets for chunk sizes to refine TextChunker heuristics.
