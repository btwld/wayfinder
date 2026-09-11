import 'dart:io';

import 'package:wayfinder_cli/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await WayfinderCli().run(arguments);
}
