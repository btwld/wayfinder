import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder/src/project/process_tree_cleanup.dart';

void main() {
  test('discovers late forks and kills the root while it is frozen', () async {
    final events = <(int, ProcessSignal)>[];
    var reads = 0;
    await cleanupPosixProcessTree(
      root: 10,
      exited: () => false,
      parents: (_) async => ++reads == 1 ? {11: 10} : {11: 10, 12: 11},
      signal: (pid, signal) {
        events.add((pid, signal));
        return true;
      },
      killRoot: () => events.add((10, ProcessSignal.sigkill)),
    );
    expect(reads, 3);
    expect(events, [
      (10, ProcessSignal.sigstop),
      (11, ProcessSignal.sigstop),
      (12, ProcessSignal.sigstop),
      (12, ProcessSignal.sigkill),
      (11, ProcessSignal.sigkill),
      (10, ProcessSignal.sigkill),
    ]);
  });

  test('reparented or reused child ids are resumed, not killed', () async {
    final events = <(int, ProcessSignal)>[];
    var reads = 0;
    await cleanupPosixProcessTree(
      root: 10,
      exited: () => false,
      parents: (_) async => ++reads == 1 ? {11: 10} : {11: 999},
      signal: (pid, signal) {
        events.add((pid, signal));
        return true;
      },
      killRoot: () => events.add((10, ProcessSignal.sigkill)),
    );
    expect(events, [
      (10, ProcessSignal.sigstop),
      (11, ProcessSignal.sigstop),
      (10, ProcessSignal.sigkill),
      (11, ProcessSignal.sigcont),
    ]);
  });

  test(
    'uses the remaining shared budget and kills verified descendants',
    () async {
      final budgets = <Duration>[];
      final events = <(int, ProcessSignal)>[];
      var elapsed = Duration.zero;
      await cleanupPosixProcessTree(
        root: 10,
        exited: () => false,
        elapsed: () => elapsed,
        parents: (budget) async {
          budgets.add(budget);
          if (budgets.length == 2) throw const FileSystemException('ps failed');
          elapsed = const Duration(milliseconds: 1500);
          return {11: 10};
        },
        signal: (pid, signal) {
          events.add((pid, signal));
          return true;
        },
        killRoot: () => events.add((10, ProcessSignal.sigkill)),
      );
      expect(budgets, [
        const Duration(seconds: 2),
        const Duration(milliseconds: 500),
      ]);
      expect(events.sublist(2), [
        (11, ProcessSignal.sigkill),
        (10, ProcessSignal.sigkill),
      ]);
    },
  );
}
