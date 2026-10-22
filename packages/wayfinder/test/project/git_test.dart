import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';

import 'support.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-git-');
  });

  tearDown(() => temp.delete(recursive: true));

  Matcher failsWith(String code) => throwsA(
    isA<WayfinderException>().having((error) => error.code, 'code', code),
  );

  test('stdout keeps Git bytes that are not UTF-8', () async {
    await fixtureGit(temp.path, ['init', '-q']);
    final bytes = [0xff, 0xfe, 0x00, 0x41, 0x80, 0x0a];
    await File(p.join(temp.path, 'blob.bin')).writeAsBytes(bytes);
    final object = await fixtureGit(temp.path, [
      'hash-object',
      '-w',
      'blob.bin',
    ]);
    final result = await runGit([
      'cat-file',
      'blob',
      object,
    ], workingDirectory: temp.path);
    expect(result.exitCode, 0);
    expect(result.stdout, bytes);
    expect(() => result.text, throwsFormatException);
  });

  test('a failing command reports its exit code and stderr', () async {
    final result = await runGit([
      'rev-parse',
      '--verify',
      'no-such-ref',
    ], workingDirectory: temp.path);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, isNotEmpty);
  });

  test('every command runs without hooks or a filesystem monitor', () async {
    final hooks = await runGit(['config', '--get', 'core.hooksPath']);
    expect(hooks.text.trim(), '/dev/null');
    final monitor = await runGit(['config', '--get', 'core.fsmonitor']);
    expect(monitor.text.trim(), 'false');
    final ext = await runGit(['config', '--get', 'protocol.ext.allow']);
    expect(ext.text.trim(), 'never');
  });

  test(
    "a repository's hooks never run",
    () async {
      await fixtureGit(temp.path, ['init', '-q']);
      await fixtureGit(temp.path, [
        'config',
        'user.email',
        'test@example.test',
      ]);
      await fixtureGit(temp.path, ['config', 'user.name', 'Wayfinder Test']);
      await fixtureGit(temp.path, ['commit', '-q', '--allow-empty', '-m', 'x']);
      final marker = File(p.join(temp.path, 'hook-ran'));
      final hook = File(
        p.join(temp.path, '.git', 'hooks', 'reference-transaction'),
      );
      await hook.writeAsString('#!/bin/sh\ntouch "${marker.path}"\n');
      await Process.run('chmod', ['+x', hook.path]);
      final head = await fixtureGit(temp.path, ['rev-parse', 'HEAD']);
      final result = await runGit([
        'update-ref',
        'refs/heads/wayfinder',
        head,
      ], workingDirectory: temp.path);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(await marker.exists(), isFalse);
      await fixtureGit(temp.path, [
        '-c',
        'core.hooksPath=${hook.parent.path}',
        'update-ref',
        'refs/heads/plain',
        head,
      ]);
      expect(await marker.exists(), isTrue, reason: 'the hook is live');
    },
    skip: Platform.isWindows ? 'hooks need a POSIX shell here' : false,
  );

  test('the environment drops GIT_* variables and never prompts', () {
    final environment = wayfinderGitEnvironment({
      'PATH': '/bin',
      'GIT_DIR': '/elsewhere/.git',
      'GIT_WORK_TREE': '/elsewhere',
      'git_askpass': '/bin/ask',
      'GIT_SSH_COMMAND': 'ssh -i key',
    });
    expect(environment, {
      'PATH': '/bin',
      'GIT_TERMINAL_PROMPT': '0',
      'GCM_INTERACTIVE': 'never',
      'GIT_SSH_COMMAND': 'ssh -o BatchMode=yes',
      'GIT_LFS_SKIP_SMUDGE': '1',
    });
  });

  test('a command sees the hardened environment', () async {
    final result = await runGit(
      ['-c', 'alias.probe=!env', 'probe'],
      workingDirectory: temp.path,
      environment: {
        ...Platform.environment,
        'GIT_WAYFINDER_PROBE': 'inherited',
        'GIT_TERMINAL_PROMPT': '1',
      },
    );
    expect(result.exitCode, 0, reason: result.stderr);
    final lines = result.text.split(RegExp(r'\r?\n'));
    expect(lines, contains('GIT_TERMINAL_PROMPT=0'));
    expect(lines, contains('GIT_SSH_COMMAND=ssh -o BatchMode=yes'));
    expect(lines, contains('GIT_LFS_SKIP_SMUDGE=1'));
    expect(lines, isNot(contains(startsWith('GIT_WAYFINDER_PROBE='))));
  });

  test('a command past its timeout is killed with git-timeout', () async {
    final watch = Stopwatch()..start();
    await expectLater(
      runGit(
        ['-c', 'alias.slow=!sleep 30', 'slow'],
        workingDirectory: temp.path,
        timeout: const Duration(milliseconds: 300),
      ),
      failsWith('git-timeout'),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('cancelling stops a running command', () async {
    final cancel = WayfinderCancellationController();
    final watch = Stopwatch()..start();
    final running = runGit(
      ['-c', 'alias.slow=!sleep 30', 'slow'],
      workingDirectory: temp.path,
      cancel: cancel,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cancel.cancel();
    await expectLater(running, failsWith('cancelled'));
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('an already cancelled command never starts', () async {
    final cancel = WayfinderCancellationController()..cancel();
    await expectLater(
      runGit(['--version'], cancel: cancel),
      failsWith('cancelled'),
    );
  });
}
