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

  test("a repository's hooks never run", () async {
    await fixtureGit(temp.path, ['init', '-q']);
    await fixtureGit(temp.path, ['config', 'user.email', 'test@example.test']);
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
  }, skip: Platform.isWindows ? 'hooks need a POSIX shell here' : false);

  test('the environment drops GIT_* variables and never prompts', () {
    final environment = wayfinderGitEnvironment({
      'PATH': '/bin',
      'GIT_DIR': '/elsewhere/.git',
      'GIT_WORK_TREE': '/elsewhere',
      'GIT_CONFIG_PARAMETERS': "'core.hookspath'='/elsewhere'",
      'git_askpass': '/bin/ask',
      'GIT_CONFIG_GLOBAL': '/home/me/work.gitconfig',
      'GIT_CONFIG_NOSYSTEM': '1',
    });
    expect(environment, {
      'PATH': '/bin',
      'GIT_CONFIG_GLOBAL': '/home/me/work.gitconfig',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_TERMINAL_PROMPT': '0',
      'GCM_INTERACTIVE': 'never',
      'GIT_SSH_COMMAND': 'ssh -o BatchMode=yes',
      'GIT_LFS_SKIP_SMUDGE': '1',
    });
  });

  group('SSH runs the command Git would choose, in batch mode', () {
    String? ssh(Map<String, String> environment, {String? configured}) =>
        wayfinderGitEnvironment(
          environment,
          sshCommand: configured,
        )['GIT_SSH_COMMAND'];

    test('an inherited GIT_SSH_COMMAND', () {
      expect(
        ssh({'GIT_SSH_COMMAND': 'ssh -i ~/.ssh/work'}),
        'ssh -i ~/.ssh/work -o BatchMode=yes',
      );
    });

    test('core.sshCommand, which GIT_SSH_COMMAND overrides', () {
      expect(
        ssh({}, configured: '"C:/Program Files/OpenSSH/ssh.exe" -i key'),
        '"C:/Program Files/OpenSSH/ssh.exe" -i key -o BatchMode=yes',
      );
      expect(
        ssh({'GIT_SSH_COMMAND': '/usr/bin/ssh'}, configured: 'ssh -i key'),
        '/usr/bin/ssh -o BatchMode=yes',
      );
    });

    test('GIT_SSH, which core.sshCommand overrides', () {
      final environment = {'GIT_SSH': "/opt/o'ssh/bin/ssh"};
      expect(ssh(environment), r"'/opt/o'\''ssh/bin/ssh' -o BatchMode=yes");
      expect(
        ssh(environment, configured: 'ssh -F cfg'),
        'ssh -F cfg -o BatchMode=yes',
      );
      expect(
        wayfinderGitEnvironment(environment),
        containsPair('GIT_SSH', "/opt/o'ssh/bin/ssh"),
      );
    });

    test('another SSH client runs unchanged', () {
      expect(ssh({}, configured: 'plink -batch'), 'plink -batch');
      expect(
        ssh({'GIT_SSH_COMMAND': 'ssh', 'GIT_SSH_VARIANT': 'putty'}),
        'ssh',
      );
      final plink = wayfinderGitEnvironment({
        'GIT_SSH': r'C:\PuTTY\plink.exe',
        'GIT_SSH_VARIANT': 'plink',
      });
      expect(plink, isNot(contains('GIT_SSH_COMMAND')));
      expect(plink, containsPair('GIT_SSH', r'C:\PuTTY\plink.exe'));
      expect(plink, containsPair('GIT_SSH_VARIANT', 'plink'));
    });
  });

  group('a remote command runs the configured SSH command', () {
    late File log;
    late Map<String, String> environment;

    setUp(() async {
      log = File(p.join(temp.path, 'ssh.log'));
      final fake = File(p.join(temp.path, 'bin', 'ssh'));
      await fake.parent.create();
      await fake.writeAsString(
        '#!/bin/sh\necho "\$*" >> "${log.path}"\nexit 255\n',
      );
      await Process.run('chmod', ['+x', fake.path]);
      final global = File(p.join(temp.path, 'global.gitconfig'));
      await global.writeAsString(
        '[core]\n\tsshCommand = ${fake.path} -i /no/such/key\n',
      );
      environment = {
        for (final MapEntry(:key, :value) in Platform.environment.entries)
          if (!key.startsWith('GIT_')) key: value,
        'GIT_CONFIG_GLOBAL': global.path,
        'GIT_CONFIG_NOSYSTEM': '1',
      };
    });

    test("core.sshCommand from Git's configuration", () async {
      final result = await runGit([
        'ls-remote',
        'ssh://example.invalid/profile.git',
      ], environment: environment);
      expect(result.exitCode, isNot(0));
      expect(
        await log.readAsString(),
        contains('-i /no/such/key -o BatchMode=yes'),
      );
    });

    test('an inherited GIT_SSH_COMMAND over it', () async {
      final result = await runGit(
        ['ls-remote', 'ssh://example.invalid/profile.git'],
        environment: {
          ...environment,
          'GIT_SSH_COMMAND': '${p.join(temp.path, 'bin', 'ssh')} -v',
        },
      );
      expect(result.exitCode, isNot(0));
      final line = await log.readAsString();
      expect(line, contains('-v -o BatchMode=yes'));
      expect(line, isNot(contains('/no/such/key')));
    });
  }, skip: Platform.isWindows ? 'the fake ssh is a POSIX shell script' : false);

  test('a command sees the hardened environment', () async {
    final result = await runGit(
      ['-c', 'alias.probe=!env', 'probe'],
      workingDirectory: temp.path,
      environment: {
        for (final MapEntry(:key, :value) in Platform.environment.entries)
          if (!key.startsWith('GIT_SSH')) key: value,
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

  test('output restarts the timeout', () async {
    final result = await runGit(
      [
        '-c',
        'alias.chatty=!for i in 1 2 3 4 5 6 7 8 9 10; do echo x; sleep 0.2; '
            'done',
        'chatty',
      ],
      workingDirectory: temp.path,
      timeout: const Duration(seconds: 1),
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.text.split('\n').where((line) => line == 'x'), hasLength(10));
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
