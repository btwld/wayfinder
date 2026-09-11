import 'dart:io';

import 'package:wayfinder/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await WayfinderCli().run(arguments);
}
