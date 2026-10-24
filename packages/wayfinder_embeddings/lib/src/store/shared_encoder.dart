import 'dart:async';

import '../embedding/base_embedder.dart';
import 'encoder.dart';

/// Runs calls one at a time, in the order they arrive.
final class _CallLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() call) {
    final result = _last.then((_) => call());
    _last = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// An open encoder that operations may share: every call into it, each
/// batch of document embeddings, each query vector and each token count,
/// waits for the call before it to finish, so two operations of one process
/// never use one model at the same time, while their other work interleaves.
///
/// [users] counts the operations holding it. Once [evicted], new
/// operations open another encoder, and the last user disposes this one.
final class SharedEncoder {
  SharedEncoder(this.opened) {
    final lock = _CallLock();
    encoder = WayfinderEncoder(
      _LockedEmbedder(opened.embedder, lock),
      (text) => lock.run(() => opened.countTokens(text)),
      opened.maxTokens,
    );
  }

  /// The encoder as its provider opened it.
  final WayfinderEncoder opened;

  /// The same encoder, with each call locked.
  late final WayfinderEncoder encoder;

  /// The operations holding it.
  int users = 0;

  /// Whether new operations must open another encoder.
  bool evicted = false;

  Future<void>? _disposal;
  final _disposing = Completer<({Future<void> disposal})>();

  /// Completes once [dispose] has disposed the embedder, with the error the
  /// disposal threw, if any.
  Future<void> get disposed =>
      _disposing.future.then((started) => started.disposal);

  /// Disposes the embedder once, however often it is called. An embedder
  /// that throws instead of returning a future fails the future, so
  /// [disposed] still completes.
  Future<void> dispose() => _disposal ??= () {
    final disposal = Future.sync(opened.embedder.dispose);
    _disposing.complete((disposal: disposal));
    return disposal;
  }();
}

/// [delegate] with each call made under [_lock]. Disposing it does nothing:
/// its [SharedEncoder] disposes the delegate.
final class _LockedEmbedder extends BaseEmbedder {
  _LockedEmbedder(this.delegate, this._lock);

  final BaseEmbedder delegate;
  final _CallLock _lock;

  @override
  String get sourceName => delegate.sourceName;

  @override
  String get modelName => delegate.modelName;

  @override
  int get dimension => delegate.dimension;

  @override
  Future<List<double>> generateEmbedding(String text) =>
      _lock.run(() => delegate.generateEmbedding(text));

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) =>
      _lock.run(() => delegate.generateEmbeddings(texts));

  @override
  Future<List<double>> generateQueryVector(String text) =>
      _lock.run(() => delegate.generateQueryVector(text));

  @override
  Future<void> dispose() async {}
}
