import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('ChunkerRegistry', () {
    test('returns each registered chunker once', () {
      final dartChunker = DartChunker();
      final markdownChunker = MarkdownChunker();
      final registry = ChunkerRegistry()
        ..registerChunker(dartChunker)
        ..registerChunker(markdownChunker);

      expect(
        registry.getAllChunkers(),
        unorderedEquals([dartChunker, markdownChunker]),
      );
    });

    test('returns an immutable chunker snapshot', () {
      final dartChunker = DartChunker();
      final markdownChunker = MarkdownChunker();
      final registry = ChunkerRegistry()
        ..registerChunker(dartChunker)
        ..registerChunker(markdownChunker);

      final chunkers = registry.getAllChunkers();

      expect(() => chunkers.add(TextChunker()), throwsUnsupportedError);
      expect(() => chunkers[0] = TextChunker(), throwsUnsupportedError);
    });

    test('supports custom chunkers that override canHandle', () {
      final customChunker = _CustomChunker();
      final registry = ChunkerRegistry()..registerChunker(customChunker);

      expect(
        registry.getChunkerForFile(
          File('example.custom'),
          contentType: 'custom-alias',
        ),
        customChunker,
      );
    });

    test('rejects blank content type and supported extension keys', () {
      final registry = ChunkerRegistry();

      expect(
        () => registry.registerChunker(_BlankContentTypeChunker()),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'contentType',
          ),
        ),
      );
      expect(
        () => registry.registerChunker(_BlankExtensionChunker()),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'supportedExtensions',
          ),
        ),
      );
      expect(registry.getAllChunkers(), isEmpty);
    });
  });
}

class _CustomChunker extends BaseChunker {
  @override
  String get contentType => 'custom';

  @override
  bool canHandle(String contentType) => contentType == 'custom-alias';

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) => const [];
}

class _BlankContentTypeChunker extends BaseChunker {
  @override
  String get contentType => ' ';

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) => const [];
}

class _BlankExtensionChunker extends BaseChunker {
  @override
  String get contentType => 'custom';

  @override
  Set<String> get supportedExtensions => {'custom', '\t'};

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) => const [];
}
