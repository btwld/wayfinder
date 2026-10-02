import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/rules/builtins.dart';
import 'package:wayfinder/src/rules/facts.dart';
import 'package:wayfinder/src/rules/structure_builtins.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  late Directory bundle;

  setUp(() async {
    bundle = await Directory.systemTemp.createTemp('wayfinder-builtins-');
  });

  tearDown(() => bundle.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File(p.joinAll([bundle.path, ...p.posix.split(path)]));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<BundleFacts> facts() async => BundleFacts.project(
    await const OkfBundleLoader().inspect(bundle.path),
    profile: EffectiveProfile.compose([bitwild]),
  );

  Map<String, List<String>> byMessageId(Iterable<Violation> violations) {
    final paths = <String, List<String>>{};
    for (final violation in violations) {
      paths.putIfAbsent(violation.messageId!, () => []).add(violation.location);
    }
    return paths;
  }

  group('matches-generated', () {
    // An asset-only directory carries an index the generator never writes.
    setUp(() async {
      await write('log.md', '# Bundle Update Log\n');
      await write(
        'notes/a.md',
        '---\ntype: Guide\ntitle: A\ndescription: A note.\nstatus: stable\n---\n',
      );
      await write('assets/x.pdf', 'pdf');
      await write('assets/index.md', '# Assets\n');
      for (final MapEntry(key: path, value: text) in generated(await facts(), {
        'generator': 'okf-index',
      }).entries) {
        await write(path, text);
      }
    });

    test('reports an index the generator does not write as extra', () async {
      final params = {'generator': 'okf-index'};
      expect(byMessageId(matchesGenerated(await facts(), params)), {
        'extra': ['assets/index.md'],
      });
    });

    test('keep exempts a path and extra: ignore skips the check', () async {
      for (final params in [
        {
          'generator': 'okf-index',
          'keep': ['assets/index.md'],
        },
        {'generator': 'okf-index', 'extra': 'ignore'},
      ]) {
        expect(
          matchesGenerated(await facts(), params),
          isEmpty,
          reason: '$params',
        );
      }
    });

    test('reports a missing or differing generated index as stale', () async {
      await write('notes/index.md', '# Edited\n');
      await File(p.join(bundle.path, 'index.md')).delete();
      final params = {'generator': 'okf-index', 'extra': 'ignore'};
      expect(byMessageId(matchesGenerated(await facts(), params)), {
        'stale': unorderedEquals(['index.md', 'notes/index.md']),
      });
    });
  });
}
