import 'dart:io';

/// Best-effort POSIX cleanup with one inspection budget. Signals and process
/// tables are injected so fork, reparent and timeout paths can be exercised.
Future<void> cleanupPosixProcessTree({
  required int root,
  required bool Function() exited,
  required Future<Map<int, int>> Function(Duration timeout) parents,
  required bool Function(int pid, ProcessSignal signal) signal,
  required void Function() killRoot,
  Duration limit = const Duration(seconds: 2),
  Duration Function()? elapsed,
}) async {
  final clock = Stopwatch()..start();
  Duration remaining() => limit - (elapsed?.call() ?? clock.elapsed);
  final stopped = <int>{};
  final killed = <int>{};
  var current = <int, int>{};
  final ancestry = <int, int>{};
  bool stillOwned(int child) {
    final seen = <int>{};
    for (var node = child; node != root;) {
      if (!seen.add(node)) return false;
      final parent = ancestry[node];
      if (parent == null || current[node] != parent) return false;
      node = parent;
    }
    return true;
  }

  try {
    if (exited()) return;
    if (!signal(root, ProcessSignal.sigstop)) return;
    stopped.add(root);
    while (!exited() && remaining() > Duration.zero) {
      current = await parents(remaining());
      if (exited()) break;
      var discovered = false;
      // Each newly discovered parent is frozen before its children. A child
      // forked before that signal appears in the next table; iterate until
      // every verified ancestor is frozen and no new descendant remains.
      var added = true;
      while (added) {
        added = false;
        for (final MapEntry(key: child, value: parent) in current.entries) {
          if (child <= 0 || stopped.contains(child)) continue;
          if (stopped.contains(parent) &&
              stillOwned(parent) &&
              signal(child, ProcessSignal.sigstop)) {
            ancestry[child] = parent;
            stopped.add(child);
            discovered = added = true;
          }
        }
      }
      if (!discovered) break;
    }
    if (!exited()) {
      for (final child in stopped.toList().reversed) {
        if (child != root &&
            stillOwned(child) &&
            signal(child, ProcessSignal.sigkill)) {
          killed.add(child);
        }
      }
    }
  } on Exception {
    // Inspection can fail or exhaust the budget. The owned root still dies.
  } finally {
    // SIGKILL works while stopped. Never resume the root into a fork window.
    if (!exited()) killRoot();
    for (final child in stopped) {
      if (child != root && !killed.contains(child) && stillOwned(child)) {
        signal(child, ProcessSignal.sigcont);
      }
    }
  }
}
