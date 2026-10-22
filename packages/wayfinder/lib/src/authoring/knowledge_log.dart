/// What a write records in the bundle's root `log.md`.
///
/// The log is authored history (guide §3.2): the writer never derives an
/// entry of its own. It writes the caller's [KnowledgeLogEntry] or
/// [KnowledgeLogEntries], okf's lifecycle entries ([lifecycle]), or nothing
/// ([none]).
sealed class KnowledgeLog {
  const KnowledgeLog();

  /// okf's own entry for each change it applies, such as `Created` or
  /// `Deprecated`, linking the concept.
  static const KnowledgeLog lifecycle = _LifecycleLog();

  /// No entry; the log keeps its text.
  static const KnowledgeLog none = _NoLog();
}

final class _LifecycleLog extends KnowledgeLog {
  const _LifecycleLog();
}

final class _NoLog extends KnowledgeLog {
  const _NoLog();
}

/// An entry the caller authored, written exactly as given: the line
/// `* **<action>**: <description>` under the writer's date heading, newest
/// first. A Profile's skill names its lead words, such as Bitwild's
/// `Creation`, `Update` and `Deprecation`.
///
/// Both texts are one line without surrounding or repeated whitespace,
/// which is how OKF writes them, and [action] holds no `**:`. A write that
/// changes no other file records no entry.
final class KnowledgeLogEntry extends KnowledgeLog {
  const KnowledgeLogEntry({required this.action, required this.description});

  final String action;

  /// Markdown, such as a link to the concept.
  final String description;
}

/// Several entries the caller authored for one write, such as Bitwild's
/// `Area created` and `Creation` for a concept in a new directory. Each is
/// written exactly as given, as a [KnowledgeLogEntry] is, under the
/// writer's one date heading, in the order given.
final class KnowledgeLogEntries extends KnowledgeLog {
  /// [entries] holds at least one entry.
  KnowledgeLogEntries(Iterable<KnowledgeLogEntry> entries)
    : entries = List.unmodifiable(entries);

  final List<KnowledgeLogEntry> entries;
}

/// The entries [log] supplies, in order; null for [KnowledgeLog.lifecycle]
/// and [KnowledgeLog.none].
List<KnowledgeLogEntry>? suppliedLogEntries(KnowledgeLog log) => switch (log) {
  final KnowledgeLogEntry entry => [entry],
  KnowledgeLogEntries(:final entries) => entries,
  _LifecycleLog() || _NoLog() => null,
};

/// Whether the writer can record each entry of [log] exactly as given.
void checkLog(KnowledgeLog log) {
  if (log case KnowledgeLogEntries(:final entries) when entries.isEmpty) {
    throw ArgumentError.value(
      entries,
      'logEntry',
      'must hold at least one entry; KnowledgeLog.none records none',
    );
  }
  for (final entry in suppliedLogEntries(log) ?? const <KnowledgeLogEntry>[]) {
    checkLogEntry(entry);
  }
}

/// Whether the writer can record [entry] exactly as given.
void checkLogEntry(KnowledgeLogEntry entry) {
  bool oneLine(String text) =>
      text.isNotEmpty && text.trim().replaceAll(RegExp(r'\s+'), ' ') == text;
  if (!oneLine(entry.action) || entry.action.contains('**:')) {
    throw ArgumentError.value(
      entry.action,
      'action',
      'must be one nonblank line without repeated whitespace or **:',
    );
  }
  if (!oneLine(entry.description)) {
    throw ArgumentError.value(
      entry.description,
      'description',
      'must be one nonblank line without repeated whitespace',
    );
  }
}
