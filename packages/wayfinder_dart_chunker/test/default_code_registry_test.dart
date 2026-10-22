import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('defaultCodeRegistry', () {
    test('routes each source type to its chunker', () {
      final registry = defaultCodeRegistry();

      expect(registry.getChunkerForFile(File('a.dart')), isA<DartChunker>());
      expect(
        registry.getChunkerForFile(File('a.ts')),
        isA<TypeScriptChunker>(),
      );
      expect(registry.getChunkerForFile(File('a.md')), isA<MarkdownChunker>());
      expect(registry.getChunkerForFile(File('a.txt')), isA<TextChunker>());
      expect(registry.getAllChunkers(), hasLength(4));
    });

    test('keeps each chunker default without a budget', () {
      final registry = defaultCodeRegistry();

      expect(
        (registry.getChunkerByType('dart')! as DartChunker).maxChunkLength,
        DartChunker().maxChunkLength,
      );
      expect(
        (registry.getChunkerByType('typescript')! as TypeScriptChunker)
            .maxChunkLength,
        TypeScriptChunker().maxChunkLength,
      );
    });

    test('applies custom chunk budgets', () {
      final registry = defaultCodeRegistry(
        dartMaxChunkLength: 80,
        typescriptMaxChunkLength: 60,
        markdownMaxChunkLength: 40,
        textMaxChunkLength: 20,
      );

      expect(
        (registry.getChunkerByType('dart')! as DartChunker).maxChunkLength,
        80,
      );
      expect(
        (registry.getChunkerByType('typescript')! as TypeScriptChunker)
            .maxChunkLength,
        60,
      );
      expect(
        (registry.getChunkerByType('markdown')! as MarkdownChunker)
            .maxChunkLength,
        40,
      );
      expect(
        (registry.getChunkerByType('text')! as TextChunker).maxChunkLength,
        20,
      );
    });

    test('rejects a non-positive Dart budget', () {
      expect(
        () => defaultCodeRegistry(dartMaxChunkLength: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
    });
  });
}
