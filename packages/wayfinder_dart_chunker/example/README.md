# Example

[`code_example.dart`](https://github.com/btwld/wayfinder/blob/main/packages/wayfinder_dart_chunker/example/code_example.dart)
previews the chunks of the checked-in Dart sample without loading a model, and
filters them by their symbol metadata. Run it from the package directory:

```bash
dart run example/code_example.dart
```

The core of it:

```dart
import 'dart:io';

import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  final registry = defaultCodeRegistry();
  final file = File('fixtures/samples/calculator.dart');
  final chunks = [
    for (final chunked in registry.chunkFiles([file])) ...chunked.chunks,
  ];
  final methods = SearchOptions(chunkTypes: ['method']);
  for (final chunk in chunks.where(methods.matchesFilters)) {
    print('${chunk.metadata['class']}.${chunk.metadata['name']} '
        'lines ${chunk.lineStart}-${chunk.lineEnd}');
  }
}
```

Ingest the chunks with `IngestionPipeline` from `wayfinder_embeddings` to embed
and search them.
