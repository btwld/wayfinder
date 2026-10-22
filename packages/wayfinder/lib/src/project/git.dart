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
/// throws the `cancelled` [WayfinderException] when [cancel] fires. A host's
/// runner should apply the hardening [runGit] applies: see
/// [wayfinderGitOptions] and [wayfinderGitEnvironment].
typedef GitRunner =
    Future<GitResult> Function(
      List<String> arguments, {
      String? workingDirectory,
      WayfinderCancellation? cancel,
    });

/// How long [runGit] lets one command run by default.
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

/// [environment] without any `GIT_*` variable, plus what keeps Git from
/// waiting for a person: no terminal or credential-manager prompt, SSH in
/// batch mode, and no Git LFS download. A Git hook or linked worktree
/// exports `GIT_DIR` and its siblings; inherited, they would point every
/// mirror command at the user's own repository. SSH still reads the user's
/// `~/.ssh/config`, and Git still reads the user's configuration and
/// credential helpers.
Map<String, String> wayfinderGitEnvironment(Map<String, String> environment) =>
    {
      for (final MapEntry(:key, :value) in environment.entries)
        if (!key.toUpperCase().startsWith('GIT_')) key: value,
      'GIT_TERMINAL_PROMPT': '0',
      'GCM_INTERACTIVE': 'never',
      'GIT_SSH_COMMAND': 'ssh -o BatchMode=yes',
      'GIT_LFS_SKIP_SMUDGE': '1',
    };

/// The default [GitRunner]: runs Git with [wayfinderGitOptions] in
/// [wayfinderGitEnvironment] of [environment], by default the process's,
/// with stdin closed. A command that outlives [timeout] is killed with its
/// children and throws the `git-timeout` [WayfinderException]; [cancel] kills
/// it the same way and throws the `cancelled` one.
Future<GitResult> runGit(
  List<String> arguments, {
  String? workingDirectory,
  WayfinderCancellation? cancel,
  Map<String, String>? environment,
  Duration timeout = wayfinderGitTimeout,
}) async {
  throwIfCancelled(cancel);
  final process = await Process.start(
    'git',
    [...wayfinderGitOptions, ...arguments],
    workingDirectory: workingDirectory,
    environment: wayfinderGitEnvironment(environment ?? Platform.environment),
    includeParentEnvironment: false,
  );
  unawaited(process.stdin.close().catchError((Object _) {}));
  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final subscriptions = [
    process.stdout.listen(
      stdout.add,
      onDone: stdoutDone.complete,
      onError: (Object error, StackTrace trace) {},
    ),
    process.stderr.listen(
      stderr.add,
      onDone: stderrDone.complete,
      onError: (Object error, StackTrace trace) {},
    ),
  ];
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

  final timer = Timer(
    timeout,
    () => stop(
      WayfinderException(
        'git-timeout',
        'git ${arguments.firstOrNull ?? ''} did not finish within '
            '${timeout.inSeconds} seconds.',
      ),
    ),
  );
  unawaited(cancel?.whenCancelled.then((_) => stop(cancelledException)));
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
    timer.cancel();
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
