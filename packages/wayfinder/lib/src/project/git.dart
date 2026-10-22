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
/// stdout, and a kill of the command's process tree.
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
  /// stops a command, then waits a few seconds for [exitCode].
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
/// processes it started ([GitProcess.kill]). Once a command exits, its
/// output is read until both streams close, or until neither has written
/// for a second, because a helper it left running, such as an SSH
/// connection master, can hold them open.
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

/// How long [runGit] keeps reading the output of an exited command after
/// the last bytes arrived.
const _drainQuiet = Duration(seconds: 1);

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
  WayfinderException? stopped;
  final stop = Completer<void>();
  void stopFor(WayfinderException reason) {
    if (exited || stopped != null) return;
    stopped = reason;
    process.kill();
    stop.complete();
  }

  Timer? silence;
  void heard() {
    silence?.cancel();
    silence = Timer(
      timeout,
      () => stopFor(
        WayfinderException(
          'git-timeout',
          'git $command wrote nothing for ${timeout.inSeconds} seconds and '
              'was stopped.',
        ),
      ),
    );
  }

  // Output past the limit fails the command even when it arrives while the
  // output drains after the command exited.
  WayfinderException? overflow;
  final stdout = BytesBuilder(copy: false);
  final stderr = _Tail(_maxErrorBytes);
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  void done(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  // Once the command exits, the output that is still arriving keeps the
  // drain going; a second without any ends it.
  final quiet = Completer<void>();
  Timer? drain;
  void drained() {
    if (!exited) return;
    drain?.cancel();
    drain = Timer(_drainQuiet, () => done(quiet));
  }

  heard();
  final subscriptions = <StreamSubscription<Object?>>[
    process.stdout.listen(
      (bytes) {
        heard();
        drained();
        if (overflow != null) return;
        if (stdout.length + bytes.length > maxOutputBytes) {
          overflow = WayfinderException(
            'git-output-too-large',
            'git $command wrote more than $maxOutputBytes bytes and was '
                'stopped.',
          );
          stopFor(overflow!);
          return;
        }
        stdout.add(bytes);
      },
      onDone: () => done(stdoutDone),
      onError: (Object error, StackTrace trace) => done(stdoutDone),
    ),
    process.stderr.listen(
      (bytes) {
        heard();
        drained();
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
  try {
    final exitCode = await Future.any<int?>([
      exit,
      stop.future.then((_) => null),
    ]);
    if (stopped case final reason?) {
      await exit.timeout(_killGrace, onTimeout: () => -1);
      throw reason;
    }
    drained();
    await Future.any([
      Future.wait([stdoutDone.future, stderrDone.future]),
      quiet.future,
    ]);
    if (overflow case final reason?) throw reason;
    return GitResult(exitCode!, stdout.takeBytes(), stderr.text);
  } finally {
    silence?.cancel();
    drain?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}

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
  _LocalGitProcess(this._process);

  final Process _process;

  @override
  IOSink get stdin => _process.stdin;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() => unawaited(_killTree(_process));
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
