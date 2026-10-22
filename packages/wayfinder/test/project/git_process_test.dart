import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder/project.dart';

void main() {
  Matcher failsWith(String code) => throwsA(
    isA<WayfinderException>().having((error) => error.code, 'code', code),
  );

  group('a host process starter', () {
    late List<_Start> starts;
    late List<_FakeProcess> processes;
    late _FakeProcess Function(int index) next;

    setUp(() {
      starts = [];
      processes = [];
      next = (_) => _FakeProcess.exiting(0);
    });

    Future<GitProcess> start(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      required Map<String, String> environment,
    }) async {
      starts.add((
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ));
      final process = next(processes.length);
      processes.add(process);
      return process;
    }

    test('starts every command with the hardening runGit applies', () async {
      next = (_) => _FakeProcess.exiting(0, stdout: ['abc\n']);
      final inherited = {
        'PATH': '/bin',
        'GIT_DIR': '/elsewhere/.git',
        'GIT_SSH_COMMAND': 'ssh -i key',
      };
      final result = await runGit(
        ['rev-parse', 'HEAD'],
        workingDirectory: '/work',
        environment: inherited,
        start: start,
      );
      expect(result.exitCode, 0);
      expect(result.text, 'abc\n');
      expect(starts, hasLength(1));
      expect(starts.single.executable, 'git');
      expect(starts.single.arguments, [
        ...wayfinderGitOptions,
        'rev-parse',
        'HEAD',
      ]);
      expect(starts.single.workingDirectory, '/work');
      expect(starts.single.environment, wayfinderGitEnvironment(inherited));
      expect(starts.single.environment, isNot(contains('GIT_DIR')));
      expect(processes.single.stdinClosed, isTrue);
    });

    test('reads core.sshCommand through it before a remote command', () async {
      next = (index) => index == 0
          ? _FakeProcess.exiting(0, stdout: ['ssh -F work.cfg\n'])
          : _FakeProcess.exiting(0);
      await runGit(
        ['clone', '--mirror', '--', 'ssh://example.test/p.git', '/tmp/m'],
        environment: {'PATH': '/bin'},
        start: start,
      );
      expect(starts.map((start) => start.arguments.skip(6).toList()), [
        ['--git-dir=/dev/null', 'config', '--get', 'core.sshCommand'],
        ['clone', '--mirror', '--', 'ssh://example.test/p.git', '/tmp/m'],
      ]);
      expect(
        starts.last.environment['GIT_SSH_COMMAND'],
        'ssh -F work.cfg -o BatchMode=yes',
      );
    });

    test('stops a command whose stdout passes maxOutputBytes, and kills its '
        'tree', () async {
      next = (_) =>
          _FakeProcess.running(stdout: List.filled(3, List.filled(400, 0x61)));
      await expectLater(
        runGit(['cat-file', 'blob', 'x'], maxOutputBytes: 1000, start: start),
        failsWith('git-output-too-large'),
      );
      expect(processes.single.kills, 1);
    });

    test('keeps exactly maxOutputBytes', () async {
      next = (_) => _FakeProcess.exiting(
        0,
        stdout: [List.filled(600, 0x61), List.filled(400, 0x62)],
      );
      final result = await runGit(
        ['cat-file', 'blob', 'x'],
        maxOutputBytes: 1000,
        start: start,
      );
      expect(result.stdout, hasLength(1000));
    });

    test('kills a silent command at its timeout', () async {
      next = (_) => _FakeProcess.running();
      await expectLater(
        runGit(
          ['fetch'],
          environment: {'GIT_SSH_COMMAND': 'ssh'},
          timeout: const Duration(milliseconds: 200),
          start: start,
        ),
        failsWith('git-timeout'),
      );
      expect(processes.single.kills, 1);
    });

    test('kills a cancelled command', () async {
      next = (_) => _FakeProcess.running();
      final cancel = WayfinderCancellationController();
      final running = runGit(['show', 'x'], cancel: cancel, start: start);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();
      await expectLater(running, failsWith('cancelled'));
      expect(processes.single.kills, 1);
    });

    test('keeps the last 64 KiB of stderr', () async {
      next = (_) => _FakeProcess.exiting(
        1,
        stderr: [
          for (var index = 0; index < 50; index++) List.filled(4096, 0x2e),
          utf8.encode('fatal: the end'),
        ],
      );
      final result = await runGit(['show', 'x'], start: start);
      expect(result.exitCode, 1);
      expect(result.stderr.length, 64 * 1024);
      expect(result.stderr, endsWith('fatal: the end'));
    });

    test('reads stdout to its end after the command exits, however long a '
        'chunk takes', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final running = runGit(['show', 'c:p.json'], start: start);
      process
        ..write('{"part":')
        ..exitWith(0);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      process.write('"rest"}');
      await process.closeOutput();
      final result = await running;
      expect(result.exitCode, 0);
      expect(result.text, '{"part":"rest"}');
      expect(process.kills, 0);
    });

    test('fails an exited command whose stdout stays open, and stops what '
        'holds it', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final watch = Stopwatch()..start();
      final running = runGit(
        ['show', 'c:p.json'],
        timeout: const Duration(seconds: 1),
        start: start,
      );
      process
        ..write('{"part":')
        ..exitWith(0);
      await expectLater(
        running,
        throwsA(
          isA<WayfinderException>()
              .having((error) => error.code, 'code', 'git-output-incomplete')
              .having(
                (error) => error.message,
                'message',
                'git show exited, but its output was still open 1 second '
                    'later, held by a process it started; that process was '
                    'stopped.',
              ),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(process.kills, 1);
    });

    test('a cancel stops the read of an exited command\'s output', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final cancel = WayfinderCancellationController();
      final running = runGit(['show', 'x'], cancel: cancel, start: start);
      process
        ..write('{"part":')
        ..exitWith(0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancel.cancel();
      await expectLater(running, failsWith('cancelled'));
      expect(process.kills, 1);
    });

    test('fails stdout that passes maxOutputBytes after the exit', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final running = runGit(
        ['cat-file', 'blob', 'x'],
        maxOutputBytes: 1000,
        start: start,
      );
      process.exitWith(0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      process
        ..write('a' * 600)
        ..write('b' * 600);
      await expectLater(running, failsWith('git-output-too-large'));
      expect(process.kills, 1);
    });

    test('fails a command whose stdout reports an error', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final running = runGit(['show', 'x'], start: start);
      process
        ..write('{"part":')
        ..failStdout()
        ..exitWith(0);
      await expectLater(running, failsWith('git-output-incomplete'));
      expect(process.kills, 1);
    });

    test('returns once an exited command\'s stderr goes quiet, though it '
        'stays open', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final watch = Stopwatch()..start();
      final running = runGit(['show', 'x'], start: start);
      process
        ..write('done\n')
        ..writeError('warning: kept open\n')
        ..exitWith(0);
      await process.closeStdout();
      final result = await running;
      expect(result.text, 'done\n');
      expect(result.stderr, 'warning: kept open\n');
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(process.kills, 0);
    });

    test('cuts stderr that is still being written at the limit, and stops '
        'its writer', () async {
      final process = _FakeProcess.running();
      next = (_) => process;
      final watch = Stopwatch()..start();
      final running = runGit(
        ['show', 'x'],
        timeout: const Duration(seconds: 1),
        start: start,
      );
      process
        ..write('done\n')
        ..exitWith(0);
      await process.closeStdout();
      final writer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => process.writeError('.'),
      );
      try {
        final result = await running;
        expect(result.exitCode, 0);
        expect(result.text, 'done\n');
        expect(result.stderr, isNotEmpty);
      } finally {
        writer.cancel();
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(process.kills, 1);
    });

    test('refuses a limit that keeps nothing', () {
      expect(
        () => runGit(['show'], maxOutputBytes: 0, start: start),
        throwsArgumentError,
      );
    });
  });

  group(
    'with the default starter',
    () {
      late Directory temp;

      setUp(() async {
        temp = await Directory.systemTemp.createTemp('wayfinder-git-process-');
      });

      tearDown(() => temp.delete(recursive: true));

      test('a command that floods stdout is stopped', () async {
        final watch = Stopwatch()..start();
        await expectLater(
          runGit(
            ['-c', 'alias.flood=!yes', 'flood'],
            workingDirectory: temp.path,
            maxOutputBytes: 1 << 16,
          ),
          failsWith('git-output-too-large'),
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      });

      test('a helper left holding stderr does not hold the command', () async {
        final watch = Stopwatch()..start();
        final result = await runGit([
          '-c',
          'alias.linger=!sleep 8 >/dev/null & echo done',
          'linger',
        ], workingDirectory: temp.path);
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.text, 'done\n');
        expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
      });

      test('a helper left holding stdout fails the command', () async {
        final watch = Stopwatch()..start();
        await expectLater(
          runGit(
            ['-c', 'alias.linger=!sleep 6 2>/dev/null & echo done', 'linger'],
            workingDirectory: temp.path,
            timeout: const Duration(seconds: 2),
          ),
          failsWith('git-output-incomplete'),
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      });
    },
    skip: Platform.isWindows ? 'the aliases are POSIX shell' : false,
  );

  group('the subcommand of a command line', () {
    test('skips global options and their values', () {
      expect(gitSubcommand(['clone', 'x']), 'clone');
      expect(gitSubcommand(['-c', 'a.b=c', '-C', '/w', 'fetch']), 'fetch');
      expect(
        gitSubcommand(['--git-dir', '/g', '--work-tree', '/w', 'show']),
        'show',
      );
      expect(
        gitSubcommand(['--git-dir=/dev/null', 'config', '--get']),
        'config',
      );
      expect(gitSubcommand(['--config-env', 'a.b=V', 'pull']), 'pull');
      expect(gitSubcommand(['--version']), isNull);
      expect(gitSubcommand([]), isNull);
    });

    test('tells a remote command from a local one', () {
      for (final remote in [
        ['clone', '--mirror', '--', 'url', 'dir'],
        ['-c', 'x=y', 'fetch', 'origin'],
        ['remote', 'update', '--prune'],
        ['ls-remote', 'url'],
        ['push'],
        ['archive', '--remote=url', 'HEAD'],
      ]) {
        expect(gitMayReachRemote(remote), isTrue, reason: remote.join(' '));
      }
      for (final local in [
        ['show', 'c:path'],
        ['cat-file', '-e', 'c'],
        ['rev-parse', '--verify', 'c'],
        ['ls-tree', '-r', 'c'],
        ['config', '--get', 'remote.origin.url'],
        ['-c', 'remote=x', 'log'],
      ]) {
        expect(gitMayReachRemote(local), isFalse, reason: local.join(' '));
      }
    });
  });

  group('the SSH command Git would choose', () {
    test('in order: GIT_SSH_COMMAND, core.sshCommand, GIT_SSH, ssh', () {
      expect(
        wayfinderSshCommand(const {
          'GIT_SSH_COMMAND': 'ssh -v',
          'GIT_SSH': '/opt/ssh',
        }, configured: 'ssh -F cfg'),
        'ssh -v -o BatchMode=yes',
      );
      expect(
        wayfinderSshCommand(const {
          'GIT_SSH': '/opt/ssh',
        }, configured: 'ssh -F cfg'),
        'ssh -F cfg -o BatchMode=yes',
      );
      expect(
        wayfinderSshCommand(const {'GIT_SSH': '/opt/ssh'}),
        "'/opt/ssh' -o BatchMode=yes",
      );
      expect(wayfinderSshCommand(const {}), 'ssh -o BatchMode=yes');
      expect(
        wayfinderSshCommand(const {
          'GIT_SSH': r'C:\PuTTY\plink.exe',
          'GIT_SSH_VARIANT': 'plink',
        }),
        isNull,
      );
    });

    test('is what the hardened environment sets', () {
      const environment = {'GIT_SSH': '/usr/bin/ssh'};
      expect(
        wayfinderGitEnvironment(environment, sshCommand: 'ssh -i k'),
        containsPair(
          'GIT_SSH_COMMAND',
          wayfinderSshCommand(environment, configured: 'ssh -i k'),
        ),
      );
    });

    group('looks core.sshCommand up', () {
      late List<List<String>> lookups;
      late GitResult answer;

      setUp(() {
        lookups = [];
        answer = GitResult(0, utf8.encode('ssh -i work\n'), '');
      });

      Future<String?> lookUp(
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String> environment = const {},
      }) => wayfinderConfiguredSshCommand(
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        run: (lookup) async {
          lookups.add(lookup);
          return answer;
        },
      );

      test('outside a repository for a clone', () async {
        expect(await lookUp(['clone', 'url', 'dir']), 'ssh -i work');
        expect(lookups, [
          ['--git-dir=/dev/null', 'config', '--get', 'core.sshCommand'],
        ]);
      });

      test('in the repository a refresh runs in', () async {
        expect(
          await lookUp(['remote', 'update'], workingDirectory: '/mirror'),
          'ssh -i work',
        );
        expect(lookups, [
          ['config', '--get', 'core.sshCommand'],
        ]);
      });

      test('never for a local command or under GIT_SSH_COMMAND', () async {
        expect(await lookUp(['show', 'c:path']), isNull);
        expect(
          await lookUp(
            ['fetch'],
            environment: const {'GIT_SSH_COMMAND': 'ssh'},
          ),
          isNull,
        );
        expect(lookups, isEmpty);
      });

      test('null when Git configures none', () async {
        answer = const GitResult(1, [], '');
        expect(await lookUp(['fetch']), isNull);
      });
    });
  });
}

typedef _Start = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String> environment,
});

/// A Git process that writes what it is given and exits with [_code], or
/// runs until it is killed.
final class _FakeProcess implements GitProcess {
  _FakeProcess._(
    List<List<int>> stdout,
    List<List<int>> stderr, {
    required int? code,
    required bool close,
  }) {
    scheduleMicrotask(() async {
      for (final chunk in stdout) {
        _stdout.add(chunk);
        await Future<void>.delayed(Duration.zero);
      }
      for (final chunk in stderr) {
        _stderr.add(chunk);
      }
      if (code == null) return;
      if (close) await _closeOutput();
      if (!_exit.isCompleted) _exit.complete(code);
    });
  }

  _FakeProcess.exiting(
    int code, {
    List<Object> stdout = const [],
    List<List<int>> stderr = const [],
    bool close = true,
  }) : this._(
         [
           for (final chunk in stdout)
             chunk is String ? utf8.encode(chunk) : chunk as List<int>,
         ],
         stderr,
         code: code,
         close: close,
       );

  _FakeProcess.running({List<List<int>> stdout = const []})
    : this._(stdout, const [], code: null, close: false);

  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  var kills = 0;
  var stdinClosed = false;

  Future<void> _closeOutput() async {
    await Future.wait([_stdout.close(), _stderr.close()]);
  }

  /// Writes [text] to stdout unless it closed.
  void write(String text) {
    if (!_stdout.isClosed) _stdout.add(utf8.encode(text));
  }

  /// Writes [text] to stderr unless it closed.
  void writeError(String text) {
    if (!_stderr.isClosed) _stderr.add(utf8.encode(text));
  }

  void failStdout() => _stdout.addError(const FileSystemException('lost'));

  void exitWith(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  Future<void> closeStdout() => _stdout.close();

  Future<void> closeOutput() => _closeOutput();

  @override
  late final IOSink stdin = IOSink(_StdinTarget(this));

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    kills++;
    unawaited(_closeOutput());
    if (!_exit.isCompleted) _exit.complete(-9);
  }
}

final class _StdinTarget implements StreamConsumer<List<int>> {
  _StdinTarget(this._process);

  final _FakeProcess _process;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async => _process.stdinClosed = true;
}
