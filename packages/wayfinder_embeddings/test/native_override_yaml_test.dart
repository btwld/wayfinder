import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/native_cli_assets.dart';

void main() {
  test('rejects runtime overrides in valid YAML flow mappings', () async {
    final root = await Directory.systemTemp.createTemp(
      'wayfinder-native-override-',
    );
    addTearDown(() => root.delete(recursive: true));
    final pubspec = File('${root.path}/pubspec.yaml');
    for (final key in llamaCppRuntimeOverrideKeys) {
      await pubspec.writeAsString(
        'hooks: {user_defines: {llamadart: {$key: value}}}\n',
      );
      await expectLater(
        verifyLlamaCppRuntime(rootPubspec: pubspec),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains(key)),
        ),
      );
    }
    await pubspec.writeAsString(
      'hooks: {user_defines: {llamadart: {llamadart_native_runtimes: [llama_cpp]}}}\n'
      '# llamadart_native_tag: value\n',
    );
    await verifyLlamaCppRuntime(rootPubspec: pubspec);
  });
}
