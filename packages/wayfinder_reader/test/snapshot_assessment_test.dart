import 'dart:async';

import 'package:test/test.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

import 'reader_test.dart' show fixture, failure;

void main() {
  test(
    'unsupported snapshots explicitly refuse the optional capability',
    () async {
      final snapshot = _UnsupportedSnapshot();
      await expectLater(
        snapshot.assess((_) => fail('unsupported backend')),
        throwsA(failure(KnowledgeFailureCode.unavailable)),
      );
    },
  );

  test(
    'late assessor errors cannot override loss of lease authority',
    () async {
      final project = MemoryKnowledgeProject(id: 'p', capture: fixture());
      final snapshot = await project.refresh();
      final entered = Completer<void>();
      final complete = Completer<void>();
      final result = snapshot.assess((_) async {
        entered.complete();
        await complete.future;
        throw StateError('late executor failure');
      });
      await entered.future;
      final rejected = expectLater(
        result,
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      project.revoke();
      complete.complete();
      await rejected;
      await project.close();
    },
  );

  test(
    'assessment is explicit, immutable and bound to the retained revision',
    () async {
      final project = MemoryKnowledgeProject(id: 'p', capture: fixture());
      addTearDown(project.close);
      final old = await project.refresh();
      expect(
        old.bundles.single.validation,
        isA<KnowledgeValidationUnavailable>(),
      );
      project.current = fixture('new');
      final next = await project.refresh();
      final result = await old.assess((capture) => capture.files.first.bytes);
      expect(result.projectId, 'p');
      expect(result.revision, old.revision);
      expect(result.revision, isNot(next.revision));
      expect(String.fromCharCodes(result.value), 'hello');
      expect(() => result.value[0] = 0, throwsUnsupportedError);
      expect(
        old.bundles.single.validation,
        isA<KnowledgeValidationUnavailable>(),
      );
    },
  );

  test(
    'manifest ignores projection and enumeration order, covers inventory bytes',
    () {
      final original = fixture();
      final reordered = KnowledgeCapture(
        files: original.files.reversed,
        bundles: original.bundles,
      );
      expect(reordered.manifestFingerprint, original.manifestFingerprint);
      expect(
        fixture('changed').manifestFingerprint,
        isNot(original.manifestFingerprint),
      );
    },
  );

  for (final end in ['release', 'revoke', 'close', 'cancel']) {
    test(
      '$end prevents late publication and drains accepted assessment',
      () async {
        final project = MemoryKnowledgeProject(id: 'p', capture: fixture());
        final snapshot = await project.refresh();
        final entered = Completer<void>();
        final complete = Completer<void>();
        final cancel = KnowledgeCancellation();
        final result = snapshot.assess((_) async {
          entered.complete();
          await complete.future;
          return 'obsolete';
        }, cancel: cancel);
        await entered.future;
        final expected = end == 'revoke'
            ? KnowledgeFailureCode.denied
            : end == 'cancel'
            ? KnowledgeFailureCode.cancelled
            : KnowledgeFailureCode.closed;
        final rejected = expectLater(result, throwsA(failure(expected)));
        var drained = false;
        final Future<void> ending;
        switch (end) {
          case 'release':
            ending = snapshot.release();
          case 'close':
            ending = project.close();
          case 'revoke':
            project.revoke();
            ending = Future.value();
          default:
            cancel.cancel();
            ending = Future.value();
        }
        unawaited(ending.then((_) => drained = true));
        await Future<void>.delayed(Duration.zero);
        if (end == 'release' || end == 'close') expect(drained, isFalse);
        complete.complete();
        await rejected;
        await ending;
        await project.close();
      },
    );
  }
}

final class _UnsupportedSnapshot implements KnowledgeProjectSnapshot {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
