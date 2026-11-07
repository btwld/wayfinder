import 'dart:async';
import 'package:test/test.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

void main() {
  test(
    'failed capture after close reports authoritative closed state',
    () async {
      final capture = Completer<KnowledgeCapture>();
      final project = _ControlledProject(capture.future);
      final refresh = project.refresh();
      final assertion = expectLater(
        refresh,
        throwsA(
          isA<KnowledgeFailure>().having(
            (e) => e.code,
            'code',
            KnowledgeFailureCode.closed,
          ),
        ),
      );
      final closing = project.close();
      capture.completeError(StateError('source failed later'));
      await assertion;
      await closing;
    },
  );
  test(
    'failed capture after revoke reports authoritative denied state',
    () async {
      final capture = Completer<KnowledgeCapture>();
      final project = _ControlledProject(capture.future);
      final refresh = project.refresh();
      final assertion = expectLater(
        refresh,
        throwsA(
          isA<KnowledgeFailure>().having(
            (e) => e.code,
            'code',
            KnowledgeFailureCode.denied,
          ),
        ),
      );
      project.revoke();
      capture.completeError(StateError('source failed later'));
      await assertion;
      await project.close();
    },
  );
  test(
    'capture failure while open preserves the original error and permits retry',
    () async {
      final capture = Completer<KnowledgeCapture>();
      final project = _ControlledProject(capture.future);
      final failure = StateError('source failure');
      final assertion = expectLater(project.refresh(), throwsA(same(failure)));
      capture.completeError(failure);
      await assertion;
      await expectLater(project.refresh(), throwsA(same(failure)));
      await project.close();
    },
  );
}

final class _ControlledProject extends CapturedKnowledgeProject {
  _ControlledProject(Future<KnowledgeCapture> result)
    : super('test', capture: () => result);
}
