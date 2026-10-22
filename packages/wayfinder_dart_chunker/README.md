# wayfinder_dart_chunker

Chunks Dart source files for
[`wayfinder_embeddings`](../wayfinder_embeddings/README.md) along the
declarations of the analyzer's AST. It is a separate package so that
`wayfinder_embeddings` does not depend on `analyzer`, and an application that
does not chunk Dart keeps its own analyzer version.

```dart
import 'dart:io';

import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';

void main() {
  final registry = defaultCodeRegistry();
  final files = Directory('lib').listSync(recursive: true).whereType<File>();
  for (final (:file, :chunks) in registry.chunkFiles(files)) {
    print('${file.path}: ${chunks.length} chunks');
  }
}
```

Ingest the chunks with `IngestionPipeline` from `wayfinder_embeddings` to
embed and search them.

`defaultCodeRegistry()` registers `DartChunker` beside the TypeScript,
Markdown and text chunkers of `wayfinder_embeddings`. Each named budget, such
as `dartMaxChunkLength`, counts non-whitespace characters; a null budget keeps
that chunker's default. Register `DartChunker()` in your own `ChunkerRegistry`
to choose the chunkers yourself.

## Chunks

`DartChunker` emits one chunk per declaration: classes, mixins, extensions,
extension types, enums, functions, getters, setters, methods, constructors,
fields, top-level variables and type aliases, plus one `directives` chunk for
the library, import, export and part directives. Chunks start at a
declaration's documentation comment or first annotation. Metadata carries
symbol facts such as `name`, `class`, `returnType` and `params`.

Containers are summarized to their documentation and signature, so their
members are not indexed twice. A function, method or constructor whose text
exceeds `maxChunkLength` (1600 non-whitespace characters by default) is
summarized the same way, with `summary` and `truncated` set in its metadata.
A file with neither declarations nor directives becomes one `file` chunk. Line numbers are 1-based.
Chunk ids are those of `wayfinder_embeddings`: stable hashes of the source path,
line range, type and content.

The analyzer parses each file on its own, without resolving imports, and
tolerates syntax errors. Run it in an ingestion step on a desktop, a server or
CI; an application that only searches stored vectors does not need it.

## Example

From this package directory, preview the chunks of the checked-in sample
without loading a model:

```bash
dart run example/code_example.dart
```

## Development

`test/sample_golden_test.dart` checks the sample's chunks against
`test/goldens/sample_chunks.json`. `test/judged_corpus_test.dart` checks that
the chunker still produces the Dart chunks of the judged retrieval corpus in
`wayfinder_embeddings`, whose qrels name those chunk ids; it skips outside a
checkout of this repository. After reviewing an intended chunk change, rewrite
both goldens from this directory and review every qrels id that moved:

```bash
UPDATE_GOLDENS=1 dart test test/sample_golden_test.dart test/judged_corpus_test.dart
```

## License

BSD 3-Clause. See `LICENSE`.
