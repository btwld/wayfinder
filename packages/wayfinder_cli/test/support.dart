import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> copyBitwildPackage(String repository) async {
  final package = Directory(p.join('..', '..', 'profiles', 'bitwild'));
  await for (final entity in package.list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(
      p.join(
        repository,
        'profiles',
        'bitwild',
        p.relative(entity.path, from: package.path),
      ),
    );
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}
