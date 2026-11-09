import 'package:okf/okf_io.dart';
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test(
    'path validation refuses retained roots before loader or write-lock access',
    () async {
      final selection = UnselectedProfile([
        EngineDiagnostic(DiagnosticCode.configMissing, 'No profile selected.'),
      ]);
      for (final validator in [
        const ProfileValidator(),
        ProfileValidator(outsideBundleExists: (_) => true),
      ]) {
        for (final fix in [false, true]) {
          await expectLater(
            validator.validate(retainedBundleRoot, selection, fix: fix),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'cause',
                'Retained bundle validation requires outsideBundleExists; its sentinel root must never be read from disk.',
              ),
            ),
          );
        }
      }
    },
  );

  test(
    'external target enumeration covers builtin fields without disk lookup',
    () {
      final bundle = OkfBundle.fromDocuments({
        'a.md': OkfDocument.parse('''---
resource: ../resource%20file.txt
sources:
  - id: one
    resource: ../source.txt
  - id: two
    resource: https://example.test/source
computation: ../computation.dart
executor: {resource: ../executor.txt}
attester: {resource: ../attester.txt}
---
[body](../ignored.txt)
'''),
        'sub/b.md': OkfDocument.parse('---\nresource: ../../source.txt\n---\n'),
      });
      final targets = externalPathTargets(bundle);
      expect(targets.toList(), [
        '../attester.txt',
        '../computation.dart',
        '../executor.txt',
        '../resource file.txt',
        '../source.txt',
      ]);
      expect(() => targets.add('../new'), throwsUnsupportedError);
    },
  );

  test('retained root refuses resolver disk fallback without observations', () {
    final edge = OkfGraph.fromBundle(
      OkfBundle.fromDocuments({
        'note.md': OkfDocument.parse('---\nresource: ../outside.txt\n---\n'),
      }),
    ).edges.single;
    expect(
      () => resolvePathTarget(
        edge,
        inBundle: (_) => false,
        rootPath: retainedBundleRoot,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'cause',
          contains('outsideBundleExists'),
        ),
      ),
    );
    expect(
      resolvePathTarget(
        edge,
        inBundle: (_) => false,
        rootPath: retainedBundleRoot,
        outsideBundleExists: (_) => true,
      ).missing,
      isFalse,
    );
  });

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
