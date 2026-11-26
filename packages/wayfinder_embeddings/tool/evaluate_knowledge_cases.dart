import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'src/knowledge_case_evaluation.dart';

/// Run from the package directory with OUTPUT and a prepared local model.
/// Evaluates dense retrieval with the memory store.
Future<void> main(List<String> args) => evaluate(args);

Future<void> evaluate(
  List<String> args, {
  Map<String, BaseStore Function(String)> additionalStores = const {},
  String fixturePath = 'fixtures/knowledge_retrieval/cases.json',
  File? modelFile,
}) async {
  final stores = <String, BaseStore Function(String)>{
    'memory': (_) => MemoryStore(),
    ...additionalStores,
  };
  if (args.length != 1) {
    throw ArgumentError('Usage: evaluate_knowledge_cases.dart OUTPUT');
  }
  final fixture = await KnowledgeCases.load(path: fixturePath);
  final directory = await Directory.systemTemp.createTemp('knowledge_cases');
  LlamaEmbedder? embedder;
  try {
    embedder = await LlamaEmbedder.open(
      modelFile: modelFile ?? defaultEmbeddingModelFile(),
    );
    final results = <String, Object?>{};
    for (final MapEntry(key: kind, value: open) in stores.entries) {
      final store = open(p.join(directory.path, kind));
      try {
        results[kind] = await fixture.evaluate(store, embedder: embedder);
      } finally {
        await store.close();
      }
    }
    final output = File(args.first);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'model': embedder.modelName, 'limit': fixture.limit, 'results': results})}\n',
    );
    stdout.writeln('Wrote knowledge retrieval cases to ${output.path}');
  } finally {
    await embedder?.dispose();
    await directory.delete(recursive: true);
  }
}
