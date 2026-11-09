import 'package:okf/okf_io.dart';
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test(
    'path validation refuses URI roots before loading even with an observation callback',
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
            validator.validate('memory:bundle', selection, fix: fix),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'cause',
                'validate requires a filesystem bundle path; use validateLoaded for in-memory input.',
              ),
            ),
          );
        }
      }
    },
  );

  test('URI root refuses resolver disk fallback without a callback', () {
    final edge = OkfGraph.fromBundle(
      OkfBundle.fromDocuments({
        'note.md': OkfDocument.parse('---\nresource: ../outside.txt\n---\n'),
      }),
    ).edges.single;
    expect(
      () => resolvePathTarget(
        edge,
        inBundle: (_) => false,
        rootPath: 'memory:bundle',
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
        rootPath: 'memory:bundle',
        outsideBundleExists: (_) => true,
      ).missing,
      isFalse,
    );
  });

  test(
    'loaded URI roots refuse disk fallback unless a callback is supplied',
    () async {
      final root = fixtureBundle(fixture('unresolved-source-path'));
      final disk = await const OkfBundleLoader().inspect(root);
      final loaded = OkfBundleLoadResult(
        rootPath: 'memory:bundle',
        bundle: disk.bundle,
        documents: disk.documents,
        indexes: disk.indexes,
        logs: disk.logs,
        assets: disk.assets,
        report: disk.report,
      );
      final selection = await selectFixture(root);
      expect(
        () => const ProfileValidator().validateLoaded(loaded, selection),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'cause',
            contains('outsideBundleExists'),
          ),
        ),
      );
      final queried = <String>[];
      ProfileValidator(
        outsideBundleExists: (path) {
          queried.add(path);
          return true;
        },
      ).validateLoaded(loaded, selection);
      expect(queried, contains('../nowhere/original.docx'));
    },
  );

  test('loaded Windows drive paths are not mistaken for URI roots', () {
    for (final root in [r'C:\knowledge', 'C:/knowledge']) {
      final loaded = OkfBundleLoadResult(
        rootPath: root,
        bundle: OkfBundle.fromDocuments({}),
        documents: {},
        indexes: {},
        logs: {},
        assets: [],
        report: OkfReport(findings: const []),
      );
      expect(
        () => const ProfileValidator().validateLoaded(
          loaded,
          UnselectedProfile([
            EngineDiagnostic(
              DiagnosticCode.configMissing,
              'No profile selected.',
            ),
          ]),
        ),
        returnsNormally,
      );
    }
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
