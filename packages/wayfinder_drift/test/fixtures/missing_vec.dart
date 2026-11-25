import 'dart:io';

import 'package:wayfinder_drift/wayfinder_drift.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

Future<void> main(List<String> args) async {
  try {
    final reader = await const SqliteGenerationFormat().open(
      Directory(args.single),
    );
    await reader.close();
    throw StateError('The index opened without the sqlite-vec native asset.');
  } on GenerationOpenException catch (error) {
    stdout.writeln(error.message);
  }
}
