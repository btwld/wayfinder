import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'validates the embeddings corpus golden before opening the model',
    () async {
      final temp = await Directory.systemTemp.createTemp('objectbox-compare-');
      addTearDown(() => temp.delete(recursive: true));
      final queries = await File(
        p.join(temp.path, 'queries.txt'),
      ).writeAsString('How do I refresh a token?\n');
      final missingModel = p.join(temp.path, 'missing.gguf');
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'tool/compare_embeddings.dart',
          '--store=objectbox',
          '--queries=${queries.path}',
          '--output=${temp.path}',
          '--model=$missingModel',
          '--reference-chunks=../wayfinder_embeddings/test/goldens/baseline_chunks.json',
          '--validate-golden',
        ],
        environment: {'UPDATE_GOLDENS': '1'},
      );
      expect(result.exitCode, 1);
      expect(result.stdout, contains('Golden comparison passed.'));
      expect(result.stderr, contains(missingModel));
    },
  );
}
