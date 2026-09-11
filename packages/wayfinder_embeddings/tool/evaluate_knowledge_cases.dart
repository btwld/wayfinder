import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'src/knowledge_case_evaluation.dart';

/// Run from the package directory with OUTPUT and optional --native.
/// Native mode compares both stores; BM25-only mode needs no embedding model.
Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      args.length > 2 ||
      (args.length == 2 && args[1] != '--native')) {
    throw ArgumentError(
      'Usage: evaluate_knowledge_cases.dart OUTPUT [--native]',
    );
  }
  final fixture = await KnowledgeCases.load();
  final directory = await Directory.systemTemp.createTemp('knowledge_cases');
  LlamaEmbedder? embedder;
  try {
    if (args.contains('--native')) {
      embedder = await LlamaEmbedder.open(
        modelFile: defaultEmbeddingModelFile(),
      );
    }
    final results = <String, Object?>{};
    for (final kind in ['memory', if (embedder != null) 'objectbox']) {
      final BaseStore store = kind == 'memory'
          ? MemoryStore()
          : ObjectBoxStore(p.join(directory.path, 'db'));
      try {
        results[kind] = await fixture.evaluate(store, embedder: embedder);
      } finally {
        await store.close();
      }
    }
    final output = File(args.first);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'model': embedder?.modelName, 'limit': fixture.limit, 'results': results})}\n',
    );
    stdout.writeln('Wrote knowledge retrieval cases to ${output.path}');
  } finally {
    await embedder?.dispose();
    await directory.delete(recursive: true);
  }
}
