import 'dart:io';

import 'package:path/path.dart' as p;

import 'exception.dart';

/// Where Wayfinder keeps per-user state: Profile sources and their locks
/// under `profiles/`, project locks under `projects/`, and the retrieval
/// library's indexes. Everything there is derived and can be rebuilt.
abstract final class WayfinderDataDirectory {
  /// `WAYFINDER_DATA_DIR` when set; otherwise
  /// `~/Library/Application Support/Wayfinder` on macOS,
  /// `$XDG_DATA_HOME/wayfinder` (default `~/.local/share/wayfinder`) on
  /// Linux, and `%LOCALAPPDATA%/Wayfinder` on Windows. Reads [environment],
  /// by default the process's, and creates nothing.
  ///
  /// Throws a `data-directory-unavailable` [WayfinderException] when none of
  /// those variables locates one.
  static Directory resolve({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final override = env['WAYFINDER_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override);
    }
    final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'];
      if (local != null) return Directory(p.join(local, 'Wayfinder'));
    } else if (home != null) {
      if (Platform.isMacOS) {
        return Directory(
          p.join(home, 'Library', 'Application Support', 'Wayfinder'),
        );
      }
      final xdg = env['XDG_DATA_HOME'];
      return Directory(
        p.join(
          xdg != null && p.isAbsolute(xdg)
              ? xdg
              : p.join(home, '.local', 'share'),
          'wayfinder',
        ),
      );
    }
    throw const WayfinderException(
      'data-directory-unavailable',
      'Cannot locate local app data. Set WAYFINDER_DATA_DIR.',
    );
  }
}
