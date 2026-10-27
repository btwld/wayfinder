import 'package:test/test.dart';
import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  test('enhanced enum fields remain indexed beside the summarized container', () {
    final chunks = DartChunker().chunkContent(
      'enum Status {\n  active(1);\n  const Status(this.code);\n  final int code;\n}\n',
      ChunkMetadata(sourcePath: 'status.dart', contentType: 'dart'),
    );
    final field = chunks.singleWhere((chunk) => chunk.type == 'field');
    expect(field.content, 'final int code;');
    expect(field.lineStart, 4);
    expect(field.lineEnd, 4);
    expect(field.metadata['enum'], 'Status');
    expect(field.metadata['names'], ['code']);
    expect(field.metadata['final'], isTrue);
    expect(
      chunks.singleWhere((chunk) => chunk.type == 'enum').content,
      'enum Status',
    );
    final ctor = chunks.singleWhere((chunk) => chunk.type == 'constructor');
    expect(ctor.metadata['enum'], 'Status');
    expect(ctor.metadata['const'], isTrue);
    expect(ctor.metadata['external'], isFalse);

    final extChunks = DartChunker().chunkContent(
      'extension type const Id(int value) {\n  const Id.named(int v) : value = v;\n}\n',
      ChunkMetadata(sourcePath: 'id.dart', contentType: 'dart'),
    );
    final extCtor = extChunks.singleWhere(
      (chunk) => chunk.type == 'constructor',
    );
    expect(extCtor.metadata['extensionType'], 'Id');
    expect(extCtor.metadata['name'], 'named');
    expect(extCtor.metadata['const'], isTrue);
    expect(extCtor.metadata['initializers'], ['value = v']);
  });
}
