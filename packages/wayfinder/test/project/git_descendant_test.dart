import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';

String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

Future<({bool running, String text})> state(int id) async {
  final result = await Process.run('ps', [
    '-ww',
    '-p',
    '$id',
    '-o',
    'stat=,command=',
  ]);
  final text = '${result.stdout}'.trim();
  return (
    running: result.exitCode == 0 && text.isNotEmpty && !text.startsWith('Z'),
    text: text,
  );
}

Future<Map<String, Object?>> exercise(String cause) async {
  final temp = await Directory.systemTemp.createTemp('wayfinder-tree-regress-');
  final helper = File(p.join(temp.path, 'ssh-helper'));
  final descendant = File(p.join(temp.path, 'owned-descendant.fifo'));
  final ids = File(p.join(temp.path, 'owned-pids'));
  final cancel = WayfinderCancellationController();
  int? helperId;
  int? firstChildId;
  int? secondChildId;
  try {
    // Wait only on the second reader so killing it first without stopping
    // the tree would let the helper exit and reparent the first.
    await Process.run('mkfifo', [descendant.path]);
    await helper.writeAsString(
      '#!/bin/sh\n'
      '/bin/sh -c ${quote('read ignored < ${quote(descendant.path)}')} '
      '</dev/null >/dev/null 2>&1 &\n'
      'first="\$!"\n'
      '/bin/sh -c ${quote('read ignored < ${quote(descendant.path)}')} '
      '</dev/null >/dev/null 2>&1 &\n'
      'second="\$!"\n'
      'printf \'%s %s %s\\n\' "\$\$" "\$first" "\$second" > ${quote(ids.path)}\n'
      'wait "\$second"\n',
    );
    await Process.run('chmod', ['+x', helper.path]);
    final finished =
        runGit(
          ['ls-remote', 'ssh://example.invalid/profile.git'],
          workingDirectory: temp.path,
          timeout: Duration(seconds: cause == 'timeout' ? 2 : 20),
          cancel: cancel,
          environment: {
            ...Platform.environment,
            'GIT_SSH_COMMAND': quote(helper.path),
            'GIT_SSH_VARIANT': 'ssh',
          },
        ).then<String?>(
          (_) => null,
          onError: (Object error) =>
              error is WayfinderException ? error.code : 'unexpected: $error',
        );
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    List<int>? numbers;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final text = (await ids.readAsString()).trim();
        if (RegExp(r'^\d+ \d+ \d+$').hasMatch(text)) {
          final parsed = text.split(' ').map(int.parse).toList();
          if (parsed.every((id) => id > 0)) {
            numbers = parsed;
            break;
          }
        }
      } on FileSystemException {
        // The helper has not written its complete readiness record yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (numbers == null) {
      cancel.cancel();
      return {
        'cause': cause,
        'pass': false,
        'error': await finished,
        'fixture_error': 'SSH fixture never became ready',
      };
    }
    helperId = numbers[0];
    firstChildId = numbers[1];
    secondChildId = numbers[2];
    final beforeFirst = await state(firstChildId);
    final beforeSecond = await state(secondChildId);
    if (cause == 'cancel') cancel.cancel();
    final code = await finished;
    final afterHelper = await state(helperId);
    final afterFirst = await state(firstChildId);
    final afterSecond = await state(secondChildId);
    return {
      'cause': cause,
      'error': code,
      'descendant_running_before': beforeFirst.running && beforeSecond.running,
      'helper_running_after': afterHelper.running,
      'descendant_running_after': afterFirst.running || afterSecond.running,
      'descendant_state_after': '${afterFirst.text} | ${afterSecond.text}',
      'pass':
          beforeFirst.running &&
          beforeSecond.running &&
          code == (cause == 'timeout' ? 'git-timeout' : 'cancelled') &&
          !afterHelper.running &&
          !afterFirst.running &&
          !afterSecond.running,
    };
  } finally {
    cancel.cancel();
    for (final (id, marker) in [
      (firstChildId, descendant.path),
      (secondChildId, descendant.path),
      (helperId, helper.path),
    ]) {
      if (id == null || id <= 0) continue;
      final current = await state(id);
      if (current.running && current.text.contains(marker)) {
        Process.killPid(id, ProcessSignal.sigkill);
      }
    }
    await temp.delete(recursive: true);
  }
}

void main() {
  for (final cause in ['timeout', 'cancel']) {
    test('the default runner kills live SSH grandchildren on $cause', () async {
      final result = await exercise(cause);
      expect(result['descendant_running_before'], isTrue, reason: '$result');
      expect(result['error'], cause == 'timeout' ? 'git-timeout' : 'cancelled');
      expect(result['helper_running_after'], isFalse, reason: '$result');
      expect(result['descendant_running_after'], isFalse, reason: '$result');
    }, skip: Platform.isWindows ? 'POSIX process-tree regression' : false);
  }
}
