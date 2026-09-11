import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_setup.dart';
import 'knowledge.dart';
import 'version.dart';

/// Fetches the repository's GitHub releases as decoded JSON.
typedef FetchReleases = Future<Object?> Function();

/// Downloads a URL's body as text.
typedef Download = Future<String> Function(Uri url);

/// Runs an installer with extra environment and inherited terminal output.
typedef RunInstaller =
    Future<int> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    );

const _repository = 'conceptadev/wayfinder';
const _tag = 'wayfinder-v';
final _stable = RegExp(r'^\d+\.\d+\.\d+$');
final _published = RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$');

/// Orders versions by semantic-version precedence; a prerelease sorts first.
int compareVersions(String a, String b) {
  (List<int>, String) parse(String version) {
    final dash = version.indexOf('-');
    final core = dash < 0 ? version : version.substring(0, dash);
    return (
      core.split('.').map(int.parse).toList(),
      dash < 0 ? '' : version.substring(dash + 1),
    );
  }

  final (aCore, aPre) = parse(a);
  final (bCore, bPre) = parse(b);
  for (var i = 0; i < 3; i++) {
    if (aCore[i] != bCore[i]) return aCore[i].compareTo(bCore[i]);
  }
  if (aPre == bPre) return 0;
  if (aPre.isEmpty) return 1;
  if (bPre.isEmpty) return -1;
  return aPre.compareTo(bPre);
}

/// Finds the newest stable Wayfinder application release.
///
/// The repository also publishes library and legacy validator releases, so this
/// filters `wayfinder-v` tags instead of trusting GitHub's single latest
/// release. Results are cached for a day in the Wayfinder data directory.
class ReleaseChecker {
  ReleaseChecker({
    required this.dataDirectory,
    FetchReleases? fetch,
    DateTime Function()? now,
    Duration timeout = const Duration(seconds: 5),
  }) : _fetch = fetch ?? (() => _fetchReleases(timeout)),
       _now = now ?? DateTime.now;

  final Directory dataDirectory;
  final FetchReleases _fetch;
  final DateTime Function() _now;

  File get _cache => File(p.join(dataDirectory.path, 'update-check.json'));

  /// The newest stable version, fetched at most daily unless [refresh].
  Future<String?> latest({bool refresh = false}) async {
    if (!refresh) {
      try {
        final cached =
            jsonDecode(await _cache.readAsString()) as Map<String, Object?>;
        final checked = DateTime.parse(cached['checked_at']! as String);
        if (_now().difference(checked) < const Duration(days: 1)) {
          return cached['latest'] as String?;
        }
      } on Object {
        // A missing or unreadable cache only means checking again.
      }
    }
    final releases = await _fetch();
    String? newest;
    if (releases is List) {
      for (final release in releases) {
        if (release is! Map ||
            release['draft'] == true ||
            release['prerelease'] == true) {
          continue;
        }
        final tag = release['tag_name'];
        if (tag is! String || !tag.startsWith(_tag)) continue;
        final version = tag.substring(_tag.length);
        if (_stable.hasMatch(version) &&
            (newest == null || compareVersions(version, newest) > 0)) {
          newest = version;
        }
      }
    }
    try {
      await dataDirectory.create(recursive: true);
      await _cache.writeAsString(
        jsonEncode({
          'checked_at': _now().toUtc().toIso8601String(),
          'latest': newest,
        }),
      );
    } on FileSystemException {
      // The answer is still valid without a cache.
    }
    return newest;
  }
}

/// Upgrades an installer-managed runtime and refreshes its agent skills.
///
/// It reruns the release's own installer, which verifies every download and
/// installs the bundled skills. A Dart installation is upgraded by pub; the
/// Homebrew formula is no longer updated, so Homebrew users reinstall with the
/// script.
class Updater {
  Updater({
    required void Function(String) out,
    required this.checker,
    required this.setup,
    String? executable,
    Download? download,
    RunInstaller? runInstaller,
    Map<String, String>? environment,
  }) : _out = out,
       executable = executable ?? Platform.resolvedExecutable,
       _download = download ?? _downloadText,
       _runInstaller = runInstaller ?? _runInheriting,
       _environment = environment ?? Platform.environment;

  final void Function(String) _out;
  final ReleaseChecker checker;
  final AgentSetup setup;
  final String executable;
  final Download _download;
  final RunInstaller _runInstaller;
  final Map<String, String> _environment;

  Future<void> run({bool check = false, String? version}) async {
    if (version != null && !_published.hasMatch(version)) {
      throw const WayfinderException(
        '--version must be a published release version.',
      );
    }
    final String? target;
    try {
      target = version ?? await checker.latest(refresh: true);
    } on Object catch (error) {
      throw WayfinderException('Could not check GitHub releases: $error');
    }
    if (target == null) {
      throw const WayfinderException(
        'No published Wayfinder release was found.',
      );
    }
    final newer = version != null
        ? version != wayfinderVersion
        : compareVersions(target, wayfinderVersion) > 0;
    if (check) {
      _out(
        newer
            ? 'Wayfinder $target is available (current $wayfinderVersion). '
                  'Run wayfinder update.'
            : 'Wayfinder $wayfinderVersion is up to date.',
      );
      return;
    }
    if (!newer) {
      _out(
        'Wayfinder $wayfinderVersion is up to date. Refreshing agent skills.',
      );
      final skills = _environment['WAYFINDER_SKILLS'] ?? 'all';
      if (skills != 'none') await setup.install(skills);
      await setup.refreshPlugin();
      return;
    }
    final path = p.normalize(executable);
    if (path.contains('${p.separator}Cellar${p.separator}')) {
      _out(
        'Wayfinder $target is available. The Homebrew formula is no longer '
        'updated: reinstall with the install script '
        '(https://github.com/conceptadev/wayfinder/blob/main/docs/install.md), '
        'then run brew uninstall wayfinder.',
      );
      return;
    }
    if (p.basenameWithoutExtension(path) == 'dart' ||
        path.contains('.pub-cache')) {
      _out(
        'Wayfinder $target is available. Run: '
        'dart pub global activate wayfinder_cli',
      );
      return;
    }
    // Installer layout: <root>/<version-id>/bin/wayfinder.
    final root = p.dirname(p.dirname(p.dirname(path)));
    final record = File(
      p.join(
        root,
        Platform.isWindows ? 'installed-bin.txt' : 'install-dir.txt',
      ),
    );
    if (!await record.exists()) {
      throw const WayfinderException(
        'Cannot tell how Wayfinder was installed. Rerun the installer from '
        'https://github.com/conceptadev/wayfinder/blob/main/docs/install.md.',
      );
    }
    final script = Platform.isWindows ? 'install.ps1' : 'install.sh';
    final body = await _download(
      Uri.parse(
        'https://raw.githubusercontent.com/$_repository/$_tag$target/tool/$script',
      ),
    );
    final temporary = await Directory.systemTemp.createTemp(
      'wayfinder-update-',
    );
    try {
      final file = File(p.join(temporary.path, script));
      await file.writeAsString(body);
      final environment = {
        'WAYFINDER_VERSION': target,
        'WAYFINDER_INSTALL_ROOT': root,
        if (!Platform.isWindows)
          'WAYFINDER_INSTALL_DIR': (await record.readAsString()).trim(),
      };
      final code = Platform.isWindows
          ? await _runInstaller('powershell', [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              file.path,
            ], environment)
          : await _runInstaller('/bin/sh', [file.path], environment);
      if (code != 0) {
        throw WayfinderException(
          'The installer failed; Wayfinder $wayfinderVersion remains installed.',
        );
      }
    } finally {
      await temporary.delete(recursive: true);
    }
    await setup.refreshPlugin();
    _out(
      'Updated Wayfinder to $target. Restart agents to load the new runtime '
      'and skills.',
    );
  }
}

Future<Object?> _fetchReleases(Duration timeout) async {
  final body = await _downloadText(
    Uri.parse(
      'https://api.github.com/repos/$_repository/releases?per_page=100',
    ),
    timeout: timeout,
    accept: 'application/vnd.github+json',
  );
  return jsonDecode(body);
}

Future<String> _downloadText(
  Uri url, {
  Duration timeout = const Duration(seconds: 30),
  String? accept,
}) async {
  const connect = Duration(seconds: 5);
  final client = HttpClient()
    ..connectionTimeout = timeout < connect ? timeout : connect;
  try {
    final request = await client.getUrl(url);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'wayfinder/$wayfinderVersion',
    );
    if (accept != null) request.headers.set(HttpHeaders.acceptHeader, accept);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw WayfinderException('$url returned HTTP ${response.statusCode}.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

Future<int> _runInheriting(
  String executable,
  List<String> arguments,
  Map<String, String> environment,
) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
