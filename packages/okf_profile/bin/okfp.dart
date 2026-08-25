import 'dart:async';
import 'dart:io';

import 'package:okf_profile/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runOkfpCli(arguments);
}
