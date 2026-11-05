/// Where a link in a document's body leads, as the reader opens it.
sealed class KnowledgeBodyLink {
  const KnowledgeBodyLink();
}

/// A file of the same bundle, at [path] relative to the project root,
/// which opens in the reader.
final class KnowledgeFileLink extends KnowledgeBodyLink {
  const KnowledgeFileLink(this.path);
  final String path;
}

/// An `http` or `https` page, which opens in the browser.
final class KnowledgeWebLink extends KnowledgeBodyLink {
  const KnowledgeWebLink(this.uri);
  final Uri uri;
}

/// A place on the same page, `#heading`, which the reader leaves alone.
final class KnowledgeAnchorLink extends KnowledgeBodyLink {
  const KnowledgeAnchorLink();
}

/// Anything else, which the reader shows as text: another scheme or a link
/// out of the bundle.
final class KnowledgeOtherLink extends KnowledgeBodyLink {
  const KnowledgeOtherLink();
}

/// Where [href], written in a bundle document's body, leads. A relative
/// path is relative to the document's file and one starting with `/` to
/// its bundle, as OKF reads them.
KnowledgeBodyLink knowledgeBodyLink(
  String bundlePath,
  String documentPath,
  String href,
) {
  const other = KnowledgeOtherLink();
  final trimmed = href.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return other;
  if (uri.hasScheme) {
    return (uri.isScheme('http') || uri.isScheme('https')) && uri.host != ''
        ? KnowledgeWebLink(uri)
        : other;
  }
  if (uri.hasAuthority) return other;
  final cut = trimmed.indexOf(RegExp(r'[?#]'));
  final target = cut < 0 ? trimmed : trimmed.substring(0, cut);
  if (target.isEmpty) {
    return uri.hasFragment ? const KnowledgeAnchorLink() : other;
  }
  // Decode one segment at a time. A decoded separator or control character
  // misses: `%2F` and `%5C` are not extra slashes, and a literal `%` is `%25`.
  final decoded = <String>[];
  for (final segment in target.split('/')) {
    final String value;
    try {
      value = segment.contains('%') ? Uri.decodeComponent(segment) : segment;
    } on ArgumentError {
      return other;
    } on FormatException {
      return other;
    }
    if (value.contains('/') ||
        value.contains(r'\') ||
        value.runes.any((rune) => rune < 32 || rune == 127)) {
      return other;
    }
    decoded.add(value);
  }
  final file = documentPath.split('/')..removeLast();
  final base = target.startsWith('/') ? _segments(bundlePath) : file;
  final resolved = <String>[...base];
  for (final segment in decoded) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (resolved.isEmpty) return other;
      resolved.removeLast();
    } else {
      resolved.add(segment);
    }
  }
  final prefix = _segments(bundlePath);
  final inBundle =
      resolved.length > prefix.length &&
      [for (var i = 0; i < prefix.length; i++) resolved[i] == prefix[i]]
          .every((same) => same);
  return inBundle ? KnowledgeFileLink(resolved.join('/')) : other;
}

List<String> _segments(String path) => [
  for (final segment in path.split('/'))
    if (segment.isNotEmpty && segment != '.') segment,
];

/// The parts of a citation `<path>:<start>-<end>` (1-based, inclusive), or
/// null when [citation] is not in that form.
///
/// The path is relative to the project root and already carries its bundle
/// prefix: a concept in bundle `docs/okf` cites as `docs/okf/<file>:3-9`.
/// Opening a citation therefore works the same for every bundle layout: hand
/// the [path] to file selection and reveal [startLine] in Source.
({String path, int startLine, int endLine})? parseKnowledgeCitation(
  String citation,
) {
  final match = RegExp(r'^(.+):([1-9][0-9]*)-([1-9][0-9]*)$')
      .firstMatch(citation);
  if (match == null) return null;
  final start = int.parse(match.group(2)!);
  final end = int.parse(match.group(3)!);
  if (end < start) return null;
  return (path: match.group(1)!, startLine: start, endLine: end);
}
