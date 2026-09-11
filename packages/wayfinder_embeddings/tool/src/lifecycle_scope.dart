import 'dart:async';

/// Utility to coordinate the disposal of multiple resources (embedders, stores,
/// file handles, etc.) in long-lived processes.
class LifecycleScope {
  final List<FutureOr<void> Function()> _disposeActions = [];

  /// Registers an arbitrary disposer callback.
  void add(FutureOr<void> Function() dispose) {
    _disposeActions.add(dispose);
  }

  /// Tracks [resource] along with a disposer that accepts the resource.
  T track<T>(T resource, FutureOr<void> Function(T resource) dispose) {
    _disposeActions.add(() => dispose(resource));
    return resource;
  }

  /// Disposes resources in reverse registration order. If a disposer throws,
  /// remaining callbacks still run and the first error is rethrown.
  Future<void> dispose() async {
    Object? firstError;
    StackTrace? firstStack;
    while (_disposeActions.isNotEmpty) {
      final dispose = _disposeActions.removeLast();
      try {
        final result = dispose();
        if (result is Future) {
          await result;
        }
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}
