import 'package:okf/okf_io.dart';
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('external observation replaces disk only for decoded outside paths', () {
    OkfGraphEdge edge(String target) => OkfGraph.fromBundle(
      OkfBundle.fromDocuments({
        'note.md': OkfDocument.parse('---\nresource: $target\n---\n'),
      }),
    ).edges.single;
    final observed = <String>[];
    PathTarget resolve(String target) => resolvePathTarget(
      edge(target),
      inBundle: (path) => path == 'present.txt',
      rootPath: '/never-read-this-root',
      outsideBundleExists: (relative) {
        observed.add(relative);
        return relative == '../present file.txt';
      },
    );
    expect(resolve('../present%20file.txt').missing, isFalse);
    expect(resolve('../absent.txt').missing, isTrue);
    expect(resolve('/present.txt'), isA<InBundlePath>());
    expect(resolve('/missing.txt').missing, isTrue);
    expect(resolve('/../escape.txt').missing, isTrue);
    expect(resolve('../bad%2Fname').missing, isTrue);
    expect(observed, ['../present file.txt', '../absent.txt']);
  });

  test(
    'validateLoaded forwards observations; default behavior stays live',
    () async {
      final root = fixtureBundle(fixture('unresolved-source-path'));
      final loaded = await const OkfBundleLoader().inspect(root);
      final selection = await selectFixture(root);
      final observed = <String>[];
      final retained = ProfileValidator(
        outsideBundleExists: (relative) {
          observed.add(relative);
          return true;
        },
      ).validateLoaded(loaded, selection);
      final live = const ProfileValidator().validateLoaded(loaded, selection);
      expect(
        observed,
        containsAll(['../wayfinder.json', '../nowhere/original.docx']),
      );
      expect(retained.findings.length, lessThan(live.findings.length));
      expect(
        retained.findings.any((f) => f.message.contains('/missing.md')),
        isTrue,
      );
      expect(
        () => ProfileValidator(
          outsideBundleExists: (_) => throw StateError('unobserved'),
        ).validateLoaded(loaded, selection),
        throwsStateError,
      );
    },
  );
}
