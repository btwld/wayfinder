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
/// throws `WayfinderException.cancelled()` when [cancel] fires. A host's
/// runner should apply the hardening [runGit] applies: see
/// [wayfinderGitOptions] and [wayfinderGitEnvironment].
typedef GitRunner =
    Future<GitResult> Function(
      List<String> arguments, {
      String? workingDirectory,
      WayfinderCancellation? cancel,
    });

/// How long [runGit] lets a command run without writing any output before
/// it stops the command. A clone that reports progress runs as long as it
/// keeps reporting.
const wayfinderGitTimeout = Duration(minutes: 5);

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
/// SSH runs the command Git itself would choose: `GIT_SSH_COMMAND`, then
/// [sshCommand], the `core.sshCommand` value of Git's configuration when the
/// caller looked it up, then `GIT_SSH`, then `ssh`. When that is OpenSSH,
/// `-o BatchMode=yes` is added to it; another SSH client, such as PuTTY's
/// `plink`, runs unchanged. SSH still reads `~/.ssh/config`, and Git still
/// reads the user's configuration and credential helpers.
Map<String, String> wayfinderGitEnvironment(
  Map<String, String> environment, {
  String? sshCommand,
}) {
  final ssh = _batchSshCommand(environment, sshCommand);
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

/// The `GIT_SSH_COMMAND` that runs the SSH command Git would choose, in
/// batch mode when it is OpenSSH. Null when Git should keep using `GIT_SSH`
/// as it is, because that program is not OpenSSH and takes no options.
String? _batchSshCommand(Map<String, String> environment, String? configured) {
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

/// Subcommands that may reach a remote, and so run SSH.
const _remoteCommands = {
  'clone',
  'fetch',
  'ls-remote',
  'pull',
  'push',
  'remote',
  'submodule',
};

/// The default [GitRunner]: runs Git with [wayfinderGitOptions] in
/// [wayfinderGitEnvironment] of [environment], by default the process's,
/// with stdin closed. Before a command that may reach a remote, it reads
/// `core.sshCommand` with one more hardened `git config` call, as that
/// command would see it, so the user's SSH command still runs in batch mode.
///
/// A command that writes no output for [timeout] is killed with its
/// children and throws the `git-timeout` [WayfinderException]; [cancel] kills
/// it the same way and throws `WayfinderException.cancelled()`.
Future<GitResult> runGit(
  List<String> arguments, {
  String? workingDirectory,
  WayfinderCancellation? cancel,
  Map<String, String>? environment,
  Duration timeout = wayfinderGitTimeout,
}) async {
  throwIfCancelled(cancel);
  final inherited = environment ?? Platform.environment;
  String? sshCommand;
  if (_nonEmpty(inherited['GIT_SSH_COMMAND']) == null &&
      _remoteCommands.contains(_subcommand(arguments))) {
    final configured = await _run(
      [
        // Outside a working directory the command, such as `clone`, reads
        // no repository's configuration; a path that is no repository keeps
        // this lookup from reading the one around the current directory.
        if (workingDirectory == null) '--git-dir=/dev/null',
        'config',
        '--get',
        'core.sshCommand',
      ],
      workingDirectory: workingDirectory,
      environment: wayfinderGitEnvironment(inherited),
      cancel: cancel,
      timeout: timeout,
    );
    if (configured.exitCode == 0) {
      sshCommand = utf8
          .decode(configured.stdout, allowMalformed: true)
          .replaceFirst(RegExp(r'\r?\n$'), '');
    }
  }
  return _run(
    arguments,
    workingDirectory: workingDirectory,
    environment: wayfinderGitEnvironment(inherited, sshCommand: sshCommand),
    cancel: cancel,
    timeout: timeout,
  );
}

/// The first argument that is not a global option or its value.
String? _subcommand(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '-c' || argument == '-C') {
      index++;
    } else if (!argument.startsWith('-')) {
      return argument;
    }
  }
  return null;
}

Future<GitResult> _run(
  List<String> arguments, {
  required String? workingDirectory,
  required Map<String, String> environment,
  required WayfinderCancellation? cancel,
  required Duration timeout,
}) async {
  throwIfCancelled(cancel);
  final process = await Process.start(
    'git',
    [...wayfinderGitOptions, ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
  );
  unawaited(process.stdin.close().catchError((Object _) {}));
  var exited = false;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  WayfinderException? stopped;
  void stop(WayfinderException reason) {
    if (exited || stopped != null) return;
    stopped = reason;
    unawaited(_killTree(process));
  }

  Timer? timer;
  void restartTimer() {
    timer?.cancel();
    timer = Timer(
      timeout,
      () => stop(
        WayfinderException(
          'git-timeout',
          'git ${_subcommand(arguments) ?? ''} wrote nothing for '
              '${timeout.inSeconds} seconds and was stopped.',
        ),
      ),
    );
  }

  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  restartTimer();
  final subscriptions = <StreamSubscription<Object?>>[
    process.stdout.listen(
      (bytes) {
        restartTimer();
        stdout.add(bytes);
      },
      onDone: stdoutDone.complete,
      onError: (Object error, StackTrace trace) {},
    ),
    process.stderr.listen(
      (bytes) {
        restartTimer();
        stderr.add(bytes);
      },
      onDone: stderrDone.complete,
      onError: (Object error, StackTrace trace) {},
    ),
    if (cancel != null)
      cancel.whenCancelled.asStream().listen(
        (_) => stop(const WayfinderException.cancelled()),
      ),
  ];
  try {
    final exitCode = await exit;
    if (stopped case final reason?) throw reason;
    await Future.wait([stdoutDone.future, stderrDone.future]);
    return GitResult(
      exitCode,
      stdout.takeBytes(),
      utf8.decode(stderr.takeBytes(), allowMalformed: true),
    );
  } finally {
    timer?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
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
