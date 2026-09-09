import 'dart:io';

/// Logger for the application.
class Logger {
  final LogLevel _level;

  /// Creates a new logger.
  Logger({LogLevel level = LogLevel.info}) : _level = level;

  /// Logs a debug message.
  void debug(String message) {
    if (_level.index <= LogLevel.debug.index) {
      _log('DEBUG', message);
    }
  }

  /// Logs an info message.
  void info(String message) {
    if (_level.index <= LogLevel.info.index) {
      _log('INFO', message);
    }
  }

  /// Logs a warning message.
  void warning(String message) {
    if (_level.index <= LogLevel.warning.index) {
      _log('WARNING', message);
    }
  }

  /// Logs an error message.
  void error(String message) {
    if (_level.index <= LogLevel.error.index) {
      _log('ERROR', message);
    }
  }

  /// Logs a message with the specified level.
  void _log(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    stdout.writeln('[$timestamp] $level: $message');
  }
}

/// Log levels for the logger.
enum LogLevel { debug, info, warning, error }
