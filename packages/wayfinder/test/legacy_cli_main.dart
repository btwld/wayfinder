import 'dart:async';
import 'dart:io';

import 'legacy_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runOkfpCli(arguments);
}
