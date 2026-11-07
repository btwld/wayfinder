import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

import '../model/knowledge_graph_scene.dart';

/// Selection and asynchronous view state shared by every reader backend.
/// Borrows [project]; closing this controller releases its own lease only.
final class KnowledgeReaderController extends ChangeNotifier {
  KnowledgeReaderController({required this.project}) {
    _revocations = project.revocations.listen((_) => _revoke());
  }
  final KnowledgeProject project;
  late final StreamSubscription<void> _revocations;
  KnowledgeProjectSnapshot? _snapshot;
  KnowledgeProjectSnapshot? get snapshot => _snapshot;
  String? _bundleId;
  KnowledgeBundleSnapshot? get bundle =>
      _bundleId == null ? null : _snapshot?.bundle(_bundleId!);
  KnowledgeResourceEntry? selectedFile;
  KnowledgeConcept? concept;
  KnowledgeSourceBytes? source;
  KnowledgeGraphScene? scene;
  Object? error;
  bool refreshing = false;
  bool loading = false;
  bool _closed = false;
  int _refreshGeneration = 0;
  int _selectionGeneration = 0;
  final _pending = <Future<void>>{};
  Future<void>? _closing;
  final _retired = <Future<void>>{};
  (Object, StackTrace)? _cleanupFailure;

  /// Browsing has no semantic-search requirement or model readiness state.
  String get searchUnavailableReason => 'Semantic search is not configured.';

  Future<void> _track(Future<void> Function() operation) {
    if (_closed) return Future.value();
    final task = Future<void>.sync(operation);
    _pending.add(task);
    unawaited(
      task.then(
        (_) => _pending.remove(task),
        onError: (Object _, StackTrace _) {
          _pending.remove(task);
        },
      ),
    );
    return task;
  }

  Future<void> refresh() => _track(() async {
    final generation = ++_refreshGeneration;
    ++_selectionGeneration;
    refreshing = true;
    loading = false;
    error = null;
    notifyListeners();
    try {
      final next = await project.refresh();
      if (_closed || generation != _refreshGeneration) {
        await _retire(next);
        return;
      }
      final previous = _snapshot;
      _snapshot = next;
      if (previous != null) _retire(previous);
      final preferred = preferredKnowledgeBundle(
        next.bundles.map((b) => b.summary),
      );
      final retained = next.bundles.where((b) => b.id == _bundleId).firstOrNull;
      _bundleId =
          retained?.id ??
          next.bundles.where((b) => b.summary == preferred).firstOrNull?.id;
      _clearSelection();
      refreshing = false;
      notifyListeners();
    } catch (failure) {
      if (_closed || generation != _refreshGeneration) return;
      if (failure is KnowledgeFailure &&
          (failure.code == KnowledgeFailureCode.denied ||
              failure.code == KnowledgeFailureCode.closed)) {
        _revoke();
      }
      error = failure;
      refreshing = false;
      notifyListeners();
    }
  });

  void selectBundle(String id) {
    if (_closed || _snapshot == null) return;
    _snapshot!.bundle(id); // Validate against this lease, not a UI label.
    ++_selectionGeneration;
    _bundleId = id;
    _clearSelection();
    error = null;
    notifyListeners();
  }

  Future<void> openFile(KnowledgeResourceEntry file) => _track(() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final generation = ++_selectionGeneration;
    selectedFile = file;
    concept = null;
    source = null;
    scene = null;
    error = null;
    loading = true;
    notifyListeners();
    try {
      final bytes = await snapshot.read(file.handle);
      KnowledgeConcept? document;
      final bundleId = file.handle.bundle;
      if (bundleId != null) {
        final selected = snapshot.bundle(bundleId);
        final match = selected.concepts
            .where((c) => '${c.id}.md' == file.handle.path)
            .firstOrNull;
        if (match != null) document = await selected.concept(match.id);
      }
      if (!_current(generation, snapshot)) return;
      source = bytes;
      concept = document;
      loading = false;
      notifyListeners();
    } catch (failure) {
      _failedSelection(generation, snapshot, failure);
    }
  });

  Future<void> openConcept(String id) async {
    final selected = bundle;
    if (selected == null) return;
    final file = selected.files
        .where((f) => f.handle.path == '$id.md')
        .firstOrNull;
    if (file != null) await openFile(file);
  }

  Future<void> showGraph() => _track(() async {
    final snapshot = _snapshot;
    final selected = bundle;
    if (snapshot == null || selected == null) return;
    final generation = ++_selectionGeneration;
    loading = true;
    scene = null;
    error = null;
    notifyListeners();
    try {
      final graph = await selected.graph();
      final next = await layOutKnowledgeGraph(
        graph,
        const KnowledgeGraphQuery(scope: KnowledgeGraphScope.whole),
      );
      if (!_current(generation, snapshot)) return;
      scene = next;
      loading = false;
      notifyListeners();
    } catch (failure) {
      _failedSelection(generation, snapshot, failure);
    }
  });

  bool _current(int generation, KnowledgeProjectSnapshot snapshot) =>
      !_closed &&
      generation == _selectionGeneration &&
      identical(snapshot, _snapshot);
  void _failedSelection(
    int generation,
    KnowledgeProjectSnapshot snapshot,
    Object failure,
  ) {
    if (!_current(generation, snapshot)) return;
    if (failure is KnowledgeFailure &&
        (failure.code == KnowledgeFailureCode.denied ||
            failure.code == KnowledgeFailureCode.closed)) {
      _revoke();
    }
    error = failure;
    loading = false;
    notifyListeners();
  }

  void _clearSelection() {
    selectedFile = null;
    concept = null;
    source = null;
    scene = null;
    loading = false;
  }

  void _revoke() {
    if (_closed) return;
    ++_refreshGeneration;
    ++_selectionGeneration;
    final previous = _snapshot;
    _snapshot = null;
    _bundleId = null;
    _clearSelection();
    refreshing = false;
    error = KnowledgeFailure(
      KnowledgeFailureCode.denied,
      'reader',
      'Source access is unavailable.',
    );
    if (previous != null) _retire(previous);
    notifyListeners();
  }

  // Observe failed cleanup immediately, including synchronous adapter throws,
  // but preserve the original error/stack for the host awaiting close().
  Future<void> _cleanUp(FutureOr<void> Function() action) =>
      Future<void>.sync(action).then<void>(
        (_) {},
        onError: (Object failure, StackTrace stack) {
          _cleanupFailure ??= (failure, stack);
        },
      );

  Future<void> _retire(KnowledgeProjectSnapshot snapshot) {
    final work = _cleanUp(snapshot.release);
    _retired.add(work);
    unawaited(work.then((_) => _retired.remove(work)));
    return work;
  }

  /// Detach widgets before awaiting. Never closes the borrowed project.
  /// Attempts every cleanup and drains accepted work, then rethrows the first
  /// cleanup failure with its original stack, if an adapter's cleanup failed.
  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    _closed = true;
    ++_refreshGeneration;
    ++_selectionGeneration;
    final snapshot = _snapshot;
    _snapshot = null;
    _clearSelection();
    unawaited(
      _drain(snapshot).then(done.complete, onError: done.completeError),
    );
    return done.future;
  }

  Future<void> _drain(KnowledgeProjectSnapshot? snapshot) async {
    final cancellation = _cleanUp(_revocations.cancel);
    if (snapshot != null) _retire(snapshot);
    await Future.wait([
      cancellation,
      for (final pending in _pending.toList()) _cleanUp(() => pending),
    ]);
    // Pending refreshes may have retired their late results while draining.
    await Future.wait(_retired.toList());
    final failure = _cleanupFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }

  @override
  void dispose() {
    // Explicit close callers own their returned error. If dispose initiates
    // asynchronous teardown, report a genuine cleanup error through Flutter.
    if (_closing == null) {
      unawaited(
        close().then<void>(
          (_) {},
          onError: (Object failure, StackTrace stack) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: failure,
                stack: stack,
                library: 'wayfinder_flutter',
                context: ErrorDescription('while closing a knowledge reader'),
              ),
            );
          },
        ),
      );
    }
    super.dispose();
  }
}
