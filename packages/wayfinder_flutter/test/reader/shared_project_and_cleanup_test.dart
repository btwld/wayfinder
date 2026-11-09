import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

import 'reader_fixture.dart';

void main() {
  test(
    'two controllers share capture, not leases or project ownership',
    () async {
      final captured = Completer<KnowledgeCapture>();
      var captures = 0;
      final project = _CapturingProject(() {
        captures++;
        return captured.future;
      });
      final a = KnowledgeReaderController(project: project);
      final b = KnowledgeReaderController(project: project);
      final aRefresh = a.refresh();
      final bRefresh = b.refresh();
      expect(captures, 1);
      captured.complete(readerFixture());
      await Future.wait([aRefresh, bRefresh]);
      final aLease = a.snapshot!;
      final bLease = b.snapshot!;
      final aBundle = aLease.bundle('docs');
      final bBundle = bLease.bundle('docs');
      final handle = bLease.files.first.handle;
      expect(identical(aLease, bLease), isFalse);
      expect(aLease.revision, bLease.revision);
      await a.openConcept('first');
      await b.openConcept('second');
      await a.close();
      a.dispose();
      await expectLater(aBundle.concept('first'), throwsA(_closed));
      expect((await bBundle.concept('second')).body, 'second body');
      expect((await bLease.read(handle)).text, contains('first body'));
      await b.openConcept('first');
      expect(b.concept!.id, 'first');
      expect(captures, 1);
      await project.close();
      expect(b.snapshot, isNull);
      expect(b.concept, isNull);
      await expectLater(bLease.read(handle), throwsA(_closed));
      await b.close();
      b.dispose();
    },
  );

  test(
    'retired release errors are observed immediately and surfaced by close',
    () async {
      final memory = MemoryKnowledgeProject(
        id: 'memory',
        capture: readerFixture(),
      );
      final first = await memory.refresh();
      final second = await memory.refresh();
      final failure = StateError('retired release failed');
      final lease = _ControlledSnapshot(
        first,
        releaseFailure: failure,
        releaseStack: StackTrace.fromString('adapter release trace'),
      );
      final project = _QueuedProject([lease, second]);
      final uncaught = <Object>[];
      Object? closeError;
      StackTrace? closeStack;
      Object? bodyError;
      final completed = Completer<void>();
      runZonedGuarded(() async {
        final controller = KnowledgeReaderController(project: project);
        try {
          await controller.refresh();
          await controller.refresh();
          await Future<void>.delayed(Duration.zero);
          try {
            await controller.close();
          } catch (error, stack) {
            closeError = error;
            closeStack = stack;
          }
        } catch (error) {
          bodyError = error;
        } finally {
          controller.dispose();
          completed.complete();
        }
      }, (error, _) => uncaught.add(error));
      await completed.future;
      expect(bodyError, isNull);
      expect(uncaught, isEmpty);
      expect(closeError, same(failure));
      expect(closeStack.toString(), contains('adapter release trace'));
      expect(lease.releaseCalls, 1);
      expect(project.closeCalls, 0);
      await project.close();
      await memory.close();
    },
  );

  test(
    'close attempts failed subscription/release cleanup and still drains reads',
    () async {
      final memory = MemoryKnowledgeProject(
        id: 'memory',
        capture: readerFixture(),
      );
      final underlying = await memory.refresh();
      final bytes = await underlying.read(underlying.files.first.handle);
      final read = Completer<KnowledgeSourceBytes>();
      final cancellationFailure = StateError(
        'subscription cancellation failed',
      );
      final releaseFailure = StateError('active release failed');
      var cancelled = false;
      final events = StreamController<void>(
        sync: true,
        onCancel: () {
          cancelled = true;
          return Future<void>.error(cancellationFailure);
        },
      );
      final lease = _ControlledSnapshot(
        underlying,
        releaseFailure: releaseFailure,
        readGate: read,
      );
      final project = _QueuedProject([lease], events: events);
      final controller = KnowledgeReaderController(project: project);
      await controller.refresh();
      final pendingRead = controller.openFile(controller.snapshot!.files.first);
      var settled = false;
      Object? closeError;
      final closing = controller.close();
      final closed = closing.then<void>(
        (_) {
          settled = true;
        },
        onError: (Object error, StackTrace _) {
          closeError = error;
          settled = true;
        },
      );
      final sameClose = controller.close();
      expect(identical(closing, sameClose), isTrue);
      await Future<void>.delayed(Duration.zero);
      final releasedBeforeRead = lease.releaseCalls;
      final settledBeforeRead = settled;
      read.complete(bytes);
      await pendingRead;
      await closed;
      await sameClose.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      expect(cancelled, isTrue);
      expect(releasedBeforeRead, 1);
      expect(settledBeforeRead, isFalse);
      expect(lease.releaseCalls, 1);
      expect(
        closeError,
        anyOf(same(cancellationFailure), same(releaseFailure)),
      );
      expect(controller.snapshot, isNull);
      expect(controller.source, isNull);
      expect(project.closeCalls, 0);
      controller.dispose();
      await project.close();
      await memory.close();
    },
  );
}

final _closed = isA<KnowledgeFailure>().having(
  (error) => error.code,
  'code',
  KnowledgeFailureCode.closed,
);

final class _CapturingProject extends CapturedKnowledgeProject {
  _CapturingProject(Future<KnowledgeCapture> Function() capture)
    : super('shared', capture: capture);
}

final class _QueuedProject implements KnowledgeProject {
  _QueuedProject(this.snapshots, {StreamController<void>? events})
    : events = events ?? StreamController<void>.broadcast(sync: true);
  final List<KnowledgeProjectSnapshot> snapshots;
  final StreamController<void> events;
  var calls = 0;
  var closeCalls = 0;
  @override
  String get id => 'queued';
  @override
  Stream<void> get revocations => events.stream;
  @override
  Future<KnowledgeProjectSnapshot> refresh({
    KnowledgeCancellation? cancel,
  }) async => snapshots[calls++];
  @override
  Future<void> close() {
    closeCalls++;
    return events.close();
  }
}

final class _ControlledSnapshot implements KnowledgeProjectSnapshot {
  _ControlledSnapshot(
    this.delegate, {
    this.releaseFailure,
    this.releaseStack,
    this.readGate,
  });
  final KnowledgeProjectSnapshot delegate;
  final Object? releaseFailure;
  final StackTrace? releaseStack;
  final Completer<KnowledgeSourceBytes>? readGate;
  var releaseCalls = 0;
  Future<void>? _release;
  @override
  String get projectId => delegate.projectId;
  @override
  String get revision => delegate.revision;
  @override
  List<KnowledgeBundleSnapshot> get bundles => delegate.bundles;
  @override
  List<KnowledgeResourceEntry> get files => delegate.files;
  @override
  KnowledgeBundleSnapshot bundle(String id) => delegate.bundle(id);
  @override
  KnowledgeRetainedBundle loadBundle(String id) => delegate.loadBundle(id);
  @override
  Map<String, Map<String, bool>> get externalPathObservations =>
      delegate.externalPathObservations;
  @override
  Future<KnowledgeSourceBytes> read(
    KnowledgeResourceHandle handle, {
    int maxBytes = 16 * 1024 * 1024,
    KnowledgeCancellation? cancel,
  }) =>
      readGate?.future ??
      delegate.read(handle, maxBytes: maxBytes, cancel: cancel);
  @override
  Future<void> release() => _release ??= () async {
    releaseCalls++;
    await delegate.release();
    if (releaseFailure case final failure?) {
      if (releaseStack case final stack?) {
        Error.throwWithStackTrace(failure, stack);
      }
      throw failure;
    }
  }();
}
