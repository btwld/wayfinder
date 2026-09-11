import 'dart:io';

import 'package:station/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await StationCli().run(arguments);
}
