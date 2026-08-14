/// One item in a directory `index.md` document.
final class OkfIndexEntry {
  /// Creates an index entry.
  const OkfIndexEntry({
    required this.type,
    required this.title,
    required this.link,
    required this.description,
  });

  /// The section heading in which the entry appears.
  final String type;

  /// The display label for the entry.
  final String title;

  /// A URL relative to the containing index.
  final String link;

  /// A short optional summary.
  final String description;
}

/// One dated item in a bundle `log.md` document.
final class OkfLogEntry {
  /// Creates a log entry.
  const OkfLogEntry({required this.date, required this.description});

  /// The UTC calendar date under which the entry appears.
  final DateTime date;

  /// The Markdown content of the list item.
  final String description;
}
