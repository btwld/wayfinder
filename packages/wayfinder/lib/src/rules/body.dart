import 'package:markdown/markdown.dart' as markdown;

/// A concept body parsed once, for the facts and builtins that read prose.
final class ParsedBody {
  ParsedBody(this.source)
    : nodes = markdown.Document(
        extensionSet: markdown.ExtensionSet.gitHubFlavored,
      ).parse(source);

  final String source;
  final List<markdown.Node> nodes;

  /// The text of each level-one heading, in body order.
  List<String> headings() => [
    for (final node in nodes)
      if (node is markdown.Element && node.tag == 'h1') node.textContent,
  ];

  /// The distinct footnote labels the body references or defines: the
  /// referenced ones first, in first-use order outside code and the footnote
  /// definitions section, then the labels only a definition carries, in
  /// source order.
  ///
  /// A reference the parser joined to its definition survives only as a
  /// `footnote-ref` element, so its label is read back from the link. One
  /// it could not join stays literal text, which also happens to adjacent
  /// references such as `[^a][^b]` when both definitions exist, so the
  /// definition is checked in the source rather than inferred from the tree.
  List<({String label, bool referenced, bool defined})> footnotes() {
    final labels = <String>{};
    void collect(markdown.Node node, {bool excluded = false}) {
      if (node case final markdown.Text text) {
        if (excluded) return;
        for (final match in _footnoteReference.allMatches(text.text)) {
          labels.add(match[1]!);
        }
      }
      if (node case final markdown.Element element) {
        if (element.attributes['class'] == 'footnote-ref') {
          final link = element.children
              ?.whereType<markdown.Element>()
              .firstOrNull;
          final href = link?.attributes['href'] ?? '';
          if (href.startsWith('#fn-')) {
            labels.add(Uri.decodeComponent(href.substring(4)));
          }
          return;
        }
        final skip =
            excluded ||
            element.tag == 'code' ||
            element.tag == 'pre' ||
            element.attributes['class'] == 'footnotes';
        for (final child in element.children ?? const <markdown.Node>[]) {
          collect(child, excluded: skip);
        }
      }
    }

    nodes.forEach(collect);
    final defined = <String>{
      for (final match in _footnoteDefinition.allMatches(
        source.replaceAll(_fencedCode, ''),
      ))
        match[1]!,
    };
    return [
      for (final label in labels)
        (label: label, referenced: true, defined: defined.contains(label)),
      for (final label in defined)
        if (!labels.contains(label))
          (label: label, referenced: false, defined: true),
    ];
  }

  late final Relationships? relationships = _parseRelationships();

  Relationships? _parseRelationships() {
    final start = nodes.indexWhere(
      (node) =>
          node is markdown.Element &&
          node.tag == 'h1' &&
          node.textContent.trim() == 'Relationships',
    );
    if (start < 0) return null;
    final end = nodes.indexWhere(
      (node) => node is markdown.Element && node.tag == 'h1',
      start + 1,
    );
    final section = nodes.sublist(start + 1, end < 0 ? nodes.length : end);
    final labels = <String>[];
    for (final node in section) {
      if (node is! markdown.Element) return const Relationships.malformed();
      if (node.attributes['class'] == 'footnotes') continue;
      if (node.tag != 'ul') return const Relationships.malformed();
      for (final item in node.children ?? const <markdown.Node>[]) {
        final label = _relationshipLabel(item);
        if (label == null) return const Relationships.malformed();
        labels.add(label);
      }
    }
    return Relationships(labels);
  }
}

final RegExp _footnoteReference = RegExp(r'\[\^([^\]]+)\]');

/// A fenced code block, so a `[^label]:` line inside one is not read as a
/// footnote definition.
final RegExp _fencedCode = RegExp(
  r'^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1',
  multiLine: true,
  dotAll: true,
);

final RegExp _footnoteDefinition = RegExp(
  r'^ {0,3}\[\^([^\]]+)\]:',
  multiLine: true,
);

String? _relationshipLabel(markdown.Node node) {
  if (node is! markdown.Element || node.tag != 'li') return null;
  var inline = node.children ?? const <markdown.Node>[];
  if (inline case [markdown.Element(tag: 'p', :final children)]) {
    inline = children ?? const <markdown.Node>[];
  }
  final before = StringBuffer();
  final after = StringBuffer();
  var links = 0;
  for (final child in inline) {
    if (child case final markdown.Element element
        when element.tag == 'a' &&
            element.attributes['href']?.trim().isNotEmpty == true &&
            element.textContent.trim().isNotEmpty) {
      links++;
    } else {
      final text = _relationshipText(child);
      if (text == null) return null;
      (links == 0 ? before : after).write(text);
    }
  }
  final match = RegExp(r'^\s*([^:\n]+):\s*$').firstMatch(before.toString());
  if (links != 1 || match == null || after.toString().trim().isNotEmpty) {
    return null;
  }
  return match.group(1)!.trim();
}

String? _relationshipText(markdown.Node node) {
  if (node case final markdown.Text text) return text.text;
  if (node is! markdown.Element ||
      const {'a', 'img', 'br'}.contains(node.tag)) {
    return null;
  }
  final text = StringBuffer();
  for (final child in node.children ?? const <markdown.Node>[]) {
    final value = _relationshipText(child);
    if (value == null) return null;
    text.write(value);
  }
  return text.toString();
}

/// The `# Relationships` section's labels, or that its grammar is broken.
final class Relationships {
  const Relationships(this.labels) : malformed = false;

  const Relationships.malformed() : labels = const <String>[], malformed = true;

  final List<String> labels;
  final bool malformed;
}
