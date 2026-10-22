import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/native_cli_assets.dart';

void main() {
  test('the NOTICE attributes the native release llamadart pins', () async {
    // The pubspec takes any llamadart 0.15 from 0.15.6 and the lockfile is
    // not committed, so a new llamadart patch release is resolved at once.
    expect(
      await resolvedLlamaCppRuntime(),
      reviewedLlamaCppRuntime,
      reason:
          'A llamadart release that pins another llamadart-native release '
          'ships other binaries, which can change vectors. Review '
          'tool/native_assets, and the knowledge store configuration version, '
          'before moving reviewedLlamaCppRuntime.',
    );
    expect(
      await File('tool/native_assets/NOTICE').readAsString(),
      contains('llamadart-native $reviewedLlamaCppRuntime'),
    );
  });

  test('stages the runtime notices in the bundle', () async {
    final temp = await Directory.systemTemp.createTemp('native-cli-assets-');
    addTearDown(() => temp.delete(recursive: true));
    final bundle = Directory(p.join(temp.path, 'bundle'));
    if (Platform.isWindows) {
      final lib = await Directory(
        p.join(bundle.path, 'lib'),
      ).create(recursive: true);
      for (final name in ['llama.dll', 'ggml.dll', 'ggml-cpu.dll']) {
        await File(p.join(lib.path, name)).writeAsString(name);
      }
    }
    await stageNativeCliAssets(Directory.current, bundle);
    final staged = Directory(
      p.join(bundle.path, 'licenses', 'embedding_runtime'),
    ).listSync().map((entry) => p.basename(entry.path)).toSet();
    expect(staged, {'NOTICE', 'llamadart-LICENSE', 'llama-cpp-LICENSE'});
    if (Platform.isWindows) {
      expect(
        File(p.join(bundle.path, 'bin', 'ggml-cpu.dll')).existsSync(),
        isTrue,
      );
    }
  });

  test('recognises the Windows CPU backend and its variants', () {
    for (final name in [
      'ggml-cpu.dll',
      'GGML-CPU.DLL',
      'ggml-cpu-haswell.dll',
      'ggml-cpu-windows-x64.dll',
    ]) {
      expect(isWindowsCpuBackend(name), isTrue, reason: name);
    }
    for (final name in [
      'ggml.dll',
      'ggml-base.dll',
      'ggml-vulkan.dll',
      'libggml-cpu.so',
      'ggml-cpu.dll.bak',
    ]) {
      expect(isWindowsCpuBackend(name), isFalse, reason: name);
    }
  });
}
