import 'dart:async';

import 'exception.dart';

/// Asks a long operation to stop. An operation checks [isCancelled] between
/// steps and stops a running child process when [whenCancelled] completes;
/// it then throws a `cancelled` [WayfinderException]. Cancelling is not a
/// rollback: what an operation already finished stays finished.
abstract interface class WayfinderCancellation {
  bool get isCancelled;

  /// Completes once, when cancellation is requested; never with an error.
  Future<void> get whenCancelled;
}

/// A [WayfinderCancellation] its owner cancels by calling [cancel].
final class WayfinderCancellationController implements WayfinderCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  /// Requests cancellation; later calls do nothing.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Throws the `cancelled` [WayfinderException] when [cancel] is cancelled.
void throwIfCancelled(WayfinderCancellation? cancel) {
  if (cancel?.isCancelled ?? false) throw cancelledException;
}

const cancelledException = WayfinderException(
  'cancelled',
  'The operation was cancelled.',
);
