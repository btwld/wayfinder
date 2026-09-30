import 'dart:io';

import 'package:knowledge_import/knowledge_import.dart' as importer;

Future<void> main(List<String> arguments) async {
  exitCode = await importer.main(arguments);
}
