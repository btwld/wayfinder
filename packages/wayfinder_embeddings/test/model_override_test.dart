import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  test(
    'new model override takes precedence without requiring an existing file',
    () {
      expect(
        defaultEmbeddingModelFile(
          environment: {
            'WAYFINDER_EMBEDDING_MODEL': '/missing/new.gguf',
            'KNOWLEDGE_EMBEDDING_MODEL': '/legacy.gguf',
          },
        ).path,
        '/missing/new.gguf',
      );
    },
  );

  test('legacy model override remains supported', () {
    expect(
      defaultEmbeddingModelFile(
        environment: {'KNOWLEDGE_EMBEDDING_MODEL': '/legacy.gguf'},
      ).path,
      '/legacy.gguf',
    );
  });

  test('an empty explicit override does not fall back to another model', () {
    expect(
      () => defaultEmbeddingModelFile(
        environment: {
          'WAYFINDER_EMBEDDING_MODEL': ' ',
          'KNOWLEDGE_EMBEDDING_MODEL': '/legacy.gguf',
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => defaultEmbeddingModelFile(
        environment: {'KNOWLEDGE_EMBEDDING_MODEL': ''},
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
