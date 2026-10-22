import 'dart:convert';
import 'dart:io';

import 'package:wayfinder/project.dart';

/// Reports, as one JSON line, whether another process holds the lock on the
/// file named by the first argument, and whether this process can take it.
Future<void> main(List<String> arguments) async {
  final file = File(arguments.single);
  final held = await WayfinderFileLock.isHeld(file);
  final lock = await WayfinderFileLock.tryExclusive(file);
  await lock?.release();
  stdout.writeln(jsonEncode({'held': held, 'acquired': lock != null}));
}
