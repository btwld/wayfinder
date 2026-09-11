import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Includes licenses for runtime dependencies compiled into a native executable.
Future<void> stageDependencyLicenses(
  Directory bundle,
  List<String> roots,
) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Cannot inventory dependency licenses: ${result.stderr}');
  }
  final graph = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final packages = {
    for (final package in graph['packages'] as List)
      package['name'] as String: package as Map<String, dynamic>,
  };
  final configUri = await Isolate.packageConfig;
  if (configUri == null) {
    throw StateError('Package configuration is unavailable.');
  }
  final config =
      jsonDecode(await File.fromUri(configUri).readAsString())
          as Map<String, dynamic>;
  final locations = {
    for (final package in config['packages'] as List)
      package['name'] as String: configUri.resolve(
        package['rootUri'] as String,
      ),
  };
  final names = <String>{};
  void visit(String name) {
    if (!names.add(name)) return;
    final package = packages[name];
    if (package == null) throw StateError('Unknown runtime dependency: $name');
    for (final dependency in package['directDependencies'] as List) {
      visit(dependency as String);
    }
  }

  roots.forEach(visit);
  final inventory = <Map<String, Object>>[];
  for (final name in names.toList()..sort()) {
    final location = locations[name];
    if (location == null) throw StateError('Missing package location: $name');
    final licenses = Directory.fromUri(location)
        .listSync()
        .whereType<File>()
        .where(
          (file) => RegExp(
            r'^(LICENSE|LICENCE|COPYING|NOTICE|COPYRIGHT)(\..*)?$',
            caseSensitive: false,
          ).hasMatch(p.basename(file.path)),
        )
        .toList();
    if (!licenses.any(
      (file) => RegExp(
        r'^(LICENSE|LICENCE|COPYING)',
        caseSensitive: false,
      ).hasMatch(p.basename(file.path)),
    )) {
      throw StateError('Missing license for runtime dependency: $name');
    }
    final output = await Directory(
      p.join(bundle.path, 'licenses', 'dart', name),
    ).create(recursive: true);
    for (final license in licenses) {
      await license.copy(p.join(output.path, p.basename(license.path)));
    }
    inventory.add({
      'package': name,
      'version': packages[name]!['version'] as String,
    });
  }
  final sdkLicense = File(
    p.join(File(Platform.resolvedExecutable).parent.parent.path, 'LICENSE'),
  );
  final sdkOutput = await Directory(
    p.join(bundle.path, 'licenses', 'dart-sdk'),
  ).create(recursive: true);
  await sdkLicense.copy(p.join(sdkOutput.path, 'LICENSE'));
  await File(
    p.join(bundle.path, 'licenses', 'dart', 'packages.json'),
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(inventory)}\n');
}
