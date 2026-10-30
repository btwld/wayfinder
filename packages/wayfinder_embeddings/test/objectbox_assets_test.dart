import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/objectbox_assets.dart';

void main() {
  test('installer archive pins match the build provenance manifest', () async {
    final manifest =
        jsonDecode(
              await File('tool/objectbox_assets/manifest.json').readAsString(),
            )
            as Map<String, dynamic>;
    final script = await File('tool/install_objectbox.sh').readAsString();
    expect(script, contains('version=${manifest['version']}'));
    final entries = manifest['artifacts'] as Map<String, dynamic>;
    final pins = RegExp(
      r'([a-z0-9-]+)\) echo ([a-f0-9]{64}) ;;',
    ).allMatches(script);
    expect(pins.length, entries.length);
    for (final pin in pins) {
      expect(entries[pin[1]]['archiveSha256'], pin[2]);
    }
  });

  test(
    'resolves the Dart objectbox the native library is pinned for',
    () async {
      // The pubspec allows any objectbox 6.x from 6.0.0-preview.5, and the
      // lockfile is not committed; the workspace root's dependency override
      // holds the Dart release the manifest pairs with the native one.
      final manifest =
          jsonDecode(
                await File(
                  'tool/objectbox_assets/manifest.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:objectbox/objectbox.dart'),
      );
      final pubspec = await File(
        p.join(p.dirname(p.dirname(library!.toFilePath())), 'pubspec.yaml'),
      ).readAsString();
      expect(
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)?[1],
        manifest['dartVersion'],
        reason:
            'Dart objectbox and the native library move together: update the '
            "workspace root's dependency override, tool/install_objectbox.sh "
            'and tool/objectbox_assets/manifest.json in one change.',
      );
    },
  );

  final libraryName = Platform.isWindows
      ? 'objectbox.dll'
      : Platform.isMacOS
      ? 'libobjectbox.dylib'
      : 'libobjectbox.so';
  test(
    'bundles verified native bytes and rejects a modified local library',
    () async {
      final temp = await Directory.systemTemp.createTemp('objectbox-assets-');
      addTearDown(() => temp.delete(recursive: true));
      final package = await Directory(p.join(temp.path, 'package')).create();
      final assets = await Directory(
        p.join(package.path, 'tool', 'objectbox_assets'),
      ).create(recursive: true);
      for (final name in ['manifest.json', 'LICENSE', 'NOTICE']) {
        await File(
          'tool/objectbox_assets/$name',
        ).copy(p.join(assets.path, name));
      }
      final lib = await Directory(p.join(package.path, 'lib')).create();
      final library = await File(
        'lib/$libraryName',
      ).copy(p.join(lib.path, libraryName));
      final bundle = Directory(p.join(temp.path, 'bundle'));
      await stageObjectBoxAssets(package, bundle);
      final installed = File(
        p.join(bundle.path, Platform.isWindows ? 'bin' : 'lib', libraryName),
      );
      expect(await installed.readAsBytes(), await library.readAsBytes());
      expect(
        await File(
          p.join(bundle.path, 'licenses', 'objectbox', 'NOTICE'),
        ).readAsString(),
        contains('ObjectBox Ltd.'),
      );
      await library.writeAsString('not the pinned native library');
      await expectLater(
        verifiedObjectBoxLibrary(package),
        throwsFormatException,
      );
      expect(await installed.length(), greaterThan(1000));
    },
    skip:
        Platform.environment['WAYFINDER_REQUIRE_NATIVE'] == '1' ||
            File('lib/$libraryName').existsSync()
        ? false
        : 'Install the pinned ObjectBox library to exercise bundle staging. '
              'Set WAYFINDER_REQUIRE_NATIVE=1 to fail instead.',
  );
}
