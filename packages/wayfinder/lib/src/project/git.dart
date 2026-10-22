import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cancellation.dart';
import 'exception.dart';

/// A finished Git command. [stdout] keeps Git's bytes, because a blob is
/// not text; [text] decodes them as UTF-8.
final class GitResult {
  const GitResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final List<int> stdout;
  final String stderr;

  /// [stdout] as UTF-8. Throws a [FormatException] on malformed bytes.
  String get text => utf8.decode(stdout);
}

/// Runs `git` with [arguments] in [workingDirectory]. The resolver's only
/// way to touch a repository, so a host can supply its own process layer and
/// a test can prove which commands ran. A runner stops the command and
/// throws `WayfinderException.cancelled()` when [cancel] fires.
///
/// A host that only needs its own way of starting processes passes a
/// [GitProcessStarter] to [runGit], which keeps every other part of its
/// hardening. A runner of its own applies the same: [wayfinderGitOptions],
/// [wayfinderGitEnvironment] with [wayfinderConfiguredSshCommand], a bound on
/// stdout that never returns part of it, and a kill of the command's
/// process tree.
typedef GitRunner =
    Future<GitResult> Function(
      List<String> arguments, {
      String? workingDirectory,
      WayfinderCancellation? cancel,
    });

/// A Git process a [GitProcessStarter] started for [runGit].
abstract interface class GitProcess {
  /// Git's standard input, which [runGit] closes at once.
  IOSink get stdin;

  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  /// Stops the process and every process it started, such as `ssh` or a
  /// remote helper, so none outlives the command. [runGit] calls it when it
  /// stops a command, then waits a few seconds for [exitCode]. It also calls
  /// it after the exit, when a process the command started still holds its
  /// output past the read's limit or the read is cancelled; a starter that
  /// can no longer reach those processes does nothing then.
  void kill();
}

/// Starts [executable] with [arguments] for [runGit], in [workingDirectory],
/// with exactly [environment]: [runGit] has already hardened it, so the
/// starter adds nothing of the parent process's environment. A host's
/// starter may add what its process layer adds to every process, such as a
/// search path, and choose which `git` runs.
typedef GitProcessStarter =
    Future<GitProcess> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      required Map<String, String> environment,
    });

/// The default [GitProcessStarter]: `Process.start` without the parent's
/// environment. Its [GitProcess.kill] stops the process and its children:
/// `taskkill /T /F` on Windows, and `pkill -KILL -P` before the process
/// itself on POSIX systems.
Future<GitProcess> startGitProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Map<String, String> environment,
}) async => _LocalGitProcess(
  await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
  ),
);

/// How long [runGit] lets a command run without writing any output before
/// it stops the command. A clone that reports progress runs as long as it
/// keeps reporting.
const wayfinderGitTimeout = Duration(minutes: 5);

/// The most stdout bytes [runGit] keeps by default, 64 MiB: far more than
/// a Profile package or skill file, and a bound on what a hostile source can
/// make it hold. A command that writes more is stopped.
const wayfinderGitMaxOutputBytes = 64 * 1024 * 1024;

/// The configuration [runGit] puts before every command: no hooks from a
/// template or global `core.hooksPath`, no filesystem monitor, and no `ext::`
/// transport, which runs an arbitrary command named by a source URL.
const wayfinderGitOptions = [
  '-c',
  'core.hooksPath=/dev/null',
  '-c',
  'core.fsmonitor=false',
  '-c',
  'protocol.ext.allow=never',
];

/// [environment] without the `GIT_*` variables that would steer a command
/// elsewhere, plus what keeps Git from waiting for a person: no terminal or
/// credential-manager prompt, SSH in batch mode, and no Git LFS download.
///
/// A Git hook or linked worktree exports `GIT_DIR` and its siblings;
/// inherited, they would point every mirror command at the user's own
/// repository. What the user chose for every Git command is kept: which
/// configuration files Git reads (`GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`
/// and `GIT_CONFIG_NOSYSTEM`) and how it runs SSH (`GIT_SSH_COMMAND`,
/// `GIT_SSH` and `GIT_SSH_VARIANT`).
///
/// SSH runs [wayfinderSshCommand]: the command Git itself would choose, with
/// [sshCommand] as the `core.sshCommand` of Git's configuration when the
/// caller looked it up ([wayfinderConfiguredSshCommand]), in batch mode when
/// it is OpenSSH. SSH still reads `~/.ssh/config`, and Git still reads the
/// user's configuration and credential helpers.
Map<String, String> wayfinderGitEnvironment(
  Map<String, String> environment, {
  String? sshCommand,
}) {
  final ssh = wayfinderSshCommand(environment, configured: sshCommand);
  return {
    for (final MapEntry(:key, :value) in environment.entries)
      if (!key.toUpperCase().startsWith('GIT_') || _kept.contains(key))
        key: value,
    'GIT_TERMINAL_PROMPT': '0',
    'GCM_INTERACTIVE': 'never',
    'GIT_SSH_COMMAND': ?ssh,
    'GIT_LFS_SKIP_SMUDGE': '1',
  };
}

const _kept = {
  'GIT_CONFIG_GLOBAL',
  'GIT_CONFIG_SYSTEM',
  'GIT_CONFIG_NOSYSTEM',
  'GIT_SSH',
  'GIT_SSH_VARIANT',
};

/// The `GIT_SSH_COMMAND` under which Git runs the SSH command it would
/// choose in [environment]: `GIT_SSH_COMMAND`, then [configured], the
/// `core.sshCommand` of Git's configuration as the command sees it, then
/// `GIT_SSH`, then `ssh`. When that is OpenSSH, `-o BatchMode=yes` is added,
/// so SSH never asks for a password or a host key; another SSH client, such
/// as PuTTY's `plink`, runs unchanged. `GIT_SSH_VARIANT` decides whether a
/// program is OpenSSH, and otherwise its name does.
///
/// Null when Git should keep running `GIT_SSH` as it is, because that
/// program is not OpenSSH and takes no options.
String? wayfinderSshCommand(
  Map<String, String> environment, {
  String? configured,
}) {
  final variant = environment['GIT_SSH_VARIANT'];
  final command =
      _nonEmpty(environment['GIT_SSH_COMMAND']) ?? _nonEmpty(configured);
  if (command != null) {
    return _isOpenSsh(_firstWord(command), variant)
        ? '$command $_batchMode'
        : command;
  }
  if (_nonEmpty(environment['GIT_SSH']) case final program?) {
    // GIT_SSH names a program, not a shell command, so quote it for one.
    return _isOpenSsh(program, variant)
        ? "'${program.replaceAll("'", r"'\''")}' $_batchMode"
        : null;
  }
  return 'ssh $_batchMode';
}

/// `core.sshCommand` as the Git command [arguments], run in
/// [workingDirectory], would see it, for [wayfinderGitEnvironment]'s
/// `sshCommand`; null when there is none to read.
///
/// It runs one more `git config` command through [run], and only when
/// [arguments] may reach a remote ([gitMayReachRemote]) and [environment]
/// sets no `GIT_SSH_COMMAND`, which overrides the configuration. Outside a
/// working directory the command, such as `clone`, reads no repository's
/// configuration, so neither does the lookup. [run] runs Git as any of
/// Wayfinder's commands runs: with [wayfinderGitOptions], in
/// [wayfinderGitEnvironment] of [environment], in [workingDirectory], and
/// without a lookup of its own.
Future<String?> wayfinderConfiguredSshCommand(
  List<String> arguments, {
  String? workingDirectory,
  required Map<String, String> environment,
  required Future<GitResult> Function(List<String> arguments) run,
}) async {
  if (_nonEmpty(environment['GIT_SSH_COMMAND']) != null ||
      !gitMayReachRemote(arguments)) {
    return null;
  }
  final configured = await run([
    // A path that is no repository keeps the lookup from reading the one
    // around the current directory.
    if (workingDirectory == null) '--git-dir=/dev/null',
    'config',
    '--get',
    'core.sshCommand',
  ]);
  if (configured.exitCode != 0) return null;
  return utf8
      .decode(configured.stdout, allowMalformed: true)
      .replaceFirst(RegExp(r'\r?\n$'), '');
}

const _batchMode = '-o BatchMode=yes';

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

/// The program a shell command line starts, with simple quoting.
String _firstWord(String command) {
  final trimmed = command.trimLeft();
  if (trimmed.startsWith('"') || trimmed.startsWith("'")) {
    final end = trimmed.indexOf(trimmed[0], 1);
    return end < 0 ? trimmed.substring(1) : trimmed.substring(1, end);
  }
  return trimmed.split(RegExp(r'\s')).first;
}

/// Whether Git treats [program] as OpenSSH, which takes `-o` options: an
/// explicit `GIT_SSH_VARIANT` decides, and otherwise the program's name.
bool _isOpenSsh(String program, String? variant) {
  if (variant != null && variant.isNotEmpty && variant != 'auto') {
    return variant == 'ssh';
  }
  final name = program.split(RegExp(r'[/\\]')).last.toLowerCase();
  return name == 'ssh' || name == 'ssh.exe';
}

/// The Git subcommands that may reach a remote, and so may run SSH: [runGit]
/// reads `core.sshCommand` before each.
///
/// This classifies the commands Wayfinder and Git name; it is no sandbox. An
/// alias or an external `git-<name>` command can reach a remote under any
/// name, so a host that gates the network allows the local subcommands it
/// knows instead of blocking these. To consent to a Profile source, answer
/// the resolver's `ProfileFetchPolicy`, which every fetch a resolution makes
/// asks first.
const wayfinderGitRemoteSubcommands = {
  'archive',
  'clone',
  'fetch',
  'fetch-pack',
  'lfs',
  'ls-remote',
  'maintenance',
  'pull',
  'push',
  'remote',
  'send-pack',
  'submodule',
};

/// Git's global options that take their value as the next argument when it
/// is not joined with `=`.
const _globalOptionsWithValue = {
  '-c',
  '-C',
  '--attr-source',
  '--config-env',
  '--git-dir',
  '--namespace',
  '--super-prefix',
  '--work-tree',
};

/// The subcommand of the Git command line [arguments]: its first argument
/// that is neither a global option nor the value of one, such as `clone` in
/// `-c protocol.version=2 clone <url>`. Null when it names none.
String? gitSubcommand(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (_globalOptionsWithValue.contains(argument)) {
      index++;
    } else if (!argument.startsWith('-')) {
      return argument;
    }
  }
  return null;
}

/// Whether the Git command line [arguments] may reach a remote: its
/// [gitSubcommand] is one of [wayfinderGitRemoteSubcommands].
bool gitMayReachRemote(List<String> arguments) =>
    wayfinderGitRemoteSubcommands.contains(gitSubcommand(arguments));

/// The default [GitRunner]: runs Git with [wayfinderGitOptions] in
/// [wayfinderGitEnvironment] of [environment], by default the process's,
/// with stdin closed. Before a command that may reach a remote, it reads
/// `core.sshCommand` with one more hardened `git config` call
/// ([wayfinderConfiguredSshCommand]), so the user's SSH command still runs
/// in batch mode.
///
/// [start] starts each process, [startGitProcess] by default; a host passes
/// its own process layer here and keeps the rest of this hardening. Stdout
/// is kept as bytes up to [maxOutputBytes]: a command that writes more is
/// stopped and throws the `git-output-too-large` [WayfinderException] rather
/// than return a cut blob. Only the last 64 KiB of stderr are kept.
///
/// A command that writes no output for [timeout] is stopped and throws
/// `git-timeout`; [cancel] stops it the same way and throws
/// `WayfinderException.cancelled()`. Stopping kills the command with the
/// processes it started ([GitProcess.kill]).
///
/// Once a command exits, its stdout is read to its end, and its stderr
/// until it closes or a second passes without any, because a helper the
/// command left running, such as an SSH connection master, can hold stderr
/// open. Both must end within ten seconds of the exit, or [timeout] when
/// that is shorter. A stdout still open then throws `git-output-incomplete`,
/// since a result never holds part of it; a stderr still being written then
/// is cut. Either way the helpers are stopped, and [cancel] still stops the
/// read.
Future<GitResult> runGit(
  List<String> arguments, {
  String? workingDirectory,
  WayfinderCancellation? cancel,
  Map<String, String>? environment,
  Duration timeout = wayfinderGitTimeout,
  int maxOutputBytes = wayfinderGitMaxOutputBytes,
  GitProcessStarter start = startGitProcess,
}) async {
  if (maxOutputBytes <= 0) {
    throw ArgumentError.value(
      maxOutputBytes,
      'maxOutputBytes',
      'must be positive',
    );
  }
  throwIfCancelled(cancel);
  final inherited = environment ?? Platform.environment;
  Future<GitResult> run(List<String> arguments, {String? sshCommand}) => _run(
    arguments,
    workingDirectory: workingDirectory,
    environment: wayfinderGitEnvironment(inherited, sshCommand: sshCommand),
    cancel: cancel,
    timeout: timeout,
    maxOutputBytes: maxOutputBytes,
    start: start,
  );
  final sshCommand = await wayfinderConfiguredSshCommand(
    arguments,
    workingDirectory: workingDirectory,
    environment: inherited,
    run: run,
  );
  return run(arguments, sshCommand: sshCommand);
}

/// The most stderr bytes [runGit] keeps: the end of what a command wrote.
const _maxErrorBytes = 64 * 1024;

/// How long [runGit] waits for a stopped command to exit.
const _killGrace = Duration(seconds: 5);

/// How long [runGit] keeps reading an exited command's stderr, once its
/// stdout closed, after the last bytes arrived.
const _drainQuiet = Duration(seconds: 1);

/// How long after a command exits [runGit] waits for its output to end,
/// unless the command's `timeout` is shorter.
const _drainLimit = Duration(seconds: 10);

Future<GitResult> _run(
  List<String> arguments, {
  required String? workingDirectory,
  required Map<String, String> environment,
  required WayfinderCancellation? cancel,
  required Duration timeout,
  required int maxOutputBytes,
  required GitProcessStarter start,
}) async {
  throwIfCancelled(cancel);
  final command = gitSubcommand(arguments) ?? '';
  final process = await start(
    'git',
    [...wayfinderGitOptions, ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
  );
  unawaited(process.stdin.close().catchError((Object _) {}));
  var exited = false;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  // Why the command, or the read of its output once it exited, ended
  // early. Stopping kills the tree: a running command with its helpers, and
  // after the exit the helpers that still hold its output.
  WayfinderException? stopped;
  final stop = Completer<void>();
  void stopFor(WayfinderException reason) {
    if (stopped != null) return;
    stopped = reason;
    process.kill();
    stop.complete();
  }

  Timer? silence;
  void heard() {
    if (exited) return;
    silence?.cancel();
    silence = Timer(timeout, () {
      if (exited) return;
      stopFor(
        WayfinderException(
          'git-timeout',
          'git $command wrote nothing for ${timeout.inSeconds} seconds and '
              'was stopped.',
        ),
      );
    });
  }

  final stdout = BytesBuilder(copy: false);
  final stderr = _Tail(_maxErrorBytes);
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  void done(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  // Set once stdout closed after the exit: a second without stderr ends
  // the read, and each chunk of stderr starts that second again.
  Completer<void>? quiet;
  Timer? hush;
  void restartQuiet() {
    final waiting = quiet;
    if (waiting == null) return;
    hush?.cancel();
    hush = Timer(_drainQuiet, () => done(waiting));
  }

  heard();
  final subscriptions = <StreamSubscription<Object?>>[
    process.stdout.listen(
      (bytes) {
        heard();
        if (stopped != null) return;
        if (stdout.length + bytes.length > maxOutputBytes) {
          stopFor(
            WayfinderException(
              'git-output-too-large',
              'git $command wrote more than $maxOutputBytes bytes and was '
                  'stopped.',
            ),
          );
          return;
        }
        stdout.add(bytes);
      },
      onDone: () => done(stdoutDone),
      onError: (Object error, StackTrace trace) => stopFor(
        WayfinderException(
          'git-output-incomplete',
          'Reading the output of git $command failed: $error',
        ),
      ),
    ),
    process.stderr.listen(
      (bytes) {
        heard();
        restartQuiet();
        stderr.add(bytes);
      },
      onDone: () => done(stderrDone),
      onError: (Object error, StackTrace trace) => done(stderrDone),
    ),
    if (cancel != null)
      cancel.whenCancelled.asStream().listen(
        (_) => stopFor(const WayfinderException.cancelled()),
      ),
  ];
  Timer? limit;
  try {
    final exitCode = await Future.any<int?>([
      exit,
      stop.future.then((_) => null),
    ]);
    if (stopped case final reason?) {
      if (!exited) await exit.timeout(_killGrace, onTimeout: () => -1);
      throw reason;
    }
    silence?.cancel();
    final drainLimit = timeout < _drainLimit ? timeout : _drainLimit;
    final limited = Completer<void>();
    limit = Timer(drainLimit, () => done(limited));
    // A result holds all of stdout, so only its end, a stop or the limit
    // ends this wait; never a pause, which a busy isolate or a host's
    // process layer can make long.
    await Future.any([stdoutDone.future, stop.future, limited.future]);
    if (stopped == null && !stdoutDone.isCompleted) {
      stopFor(
        WayfinderException(
          'git-output-incomplete',
          'git $command exited, but its output was still open '
              '${_describe(drainLimit)} later, held by a process it started; '
              'that process was stopped.',
        ),
      );
    }
    if (stopped case final reason?) throw reason;
    final waiting = quiet = Completer<void>();
    restartQuiet();
    await Future.any([
      stderrDone.future,
      waiting.future,
      stop.future,
      limited.future,
    ]);
    if (stopped case final reason?) throw reason;
    // Stderr still being written at the limit is cut, and its writer
    // stopped.
    if (!stderrDone.isCompleted && !waiting.isCompleted) process.kill();
    return GitResult(exitCode!, stdout.takeBytes(), stderr.text);
  } finally {
    silence?.cancel();
    hush?.cancel();
    limit?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}

String _describe(Duration duration) => duration.inMilliseconds % 1000 == 0
    ? '${duration.inSeconds} second${duration.inSeconds == 1 ? '' : 's'}'
    : '${duration.inMilliseconds} milliseconds';

/// The last [limit] bytes written to it.
final class _Tail {
  _Tail(this.limit);

  final int limit;
  final _bytes = BytesBuilder(copy: false);

  void add(List<int> bytes) {
    _bytes.add(bytes);
    if (_bytes.length > 2 * limit) {
      final all = _bytes.takeBytes();
      _bytes.add(Uint8List.sublistView(all, all.length - limit));
    }
  }

  /// What was kept, as UTF-8 that tolerates a character cut at its start.
  String get text {
    final all = _bytes.takeBytes();
    return utf8.decode(
      all.length > limit ? Uint8List.sublistView(all, all.length - limit) : all,
      allowMalformed: true,
    );
  }
}

final class _LocalGitProcess implements GitProcess {
  _LocalGitProcess(this._process) {
    unawaited(_process.exitCode.then((_) => _exited = true));
  }

  final Process _process;
  var _exited = false;

  @override
  IOSink get stdin => _process.stdin;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  // Once the process exited, the processes it started have another parent
  // and its ID may name another process, so there is no tree left to kill;
  // runGit closes its end of the pipes instead.
  @override
  void kill() {
    if (!_exited) unawaited(_killTree(_process));
  }
}

/// Kills [process] and the helpers Git started, such as `ssh` or a remote
/// helper, so none outlives the command. Returns once the kill is sent.
Future<void> _killTree(Process process) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/T', '/F', '/PID', '${process.pid}']);
    } else {
      await Process.run('pkill', ['-KILL', '-P', '${process.pid}']);
    }
  } on ProcessException {
    // The tree kill is best effort; the process itself is killed below.
  }
  process.kill(ProcessSignal.sigkill);
}
