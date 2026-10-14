import 'package:markdown/markdown.dart' as markdown;

final class ParsedBody {
  ParsedBody(this.source)
    : nodes = markdown.Document(
        extensionSet: markdown.ExtensionSet.gitHubFlavored,
      ).parse(source);

  final String source;
  final List<markdown.Node> nodes;

  List<String> headings() => [
    for (final node in nodes)
      if (node is markdown.Element && node.tag == 'h1') node.textContent,
  ];

  List<String> links() {
    final targets = <String>[];
    void collect(markdown.Node node) {
      if (node is! markdown.Element) return;
      if (node.tag == 'a') {
        if (node.attributes['href'] case final href?) targets.add(href);
      }
      node.children?.forEach(collect);
    }

    nodes.forEach(collect);
    return targets;
  }

  /// A reference the parser joined to its definition survives only as a
  /// `footnote-ref` element, so its label is read back from the link, and
  /// the join proves the definition wherever it sits, a blockquote included.
  /// One it could not join stays literal text, which also happens to
  /// adjacent references such as `[^a][^b]` when both definitions exist, so
  /// its definition is checked in the source rather than inferred from the
  /// tree.
  List<({String label, bool referenced, bool defined})> footnotes() {
    final labels = <String>{};
    final joined = <String>{};
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
            final label = Uri.decodeComponent(href.substring(4));
            labels.add(label);
            joined.add(label);
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
    final defined = _definitions(source.replaceAll(_fencedCode, ''));
    return [
      for (final label in labels)
        (
          label: label,
          referenced: true,
          defined: joined.contains(label) || defined.contains(label),
        ),
      for (final label in defined)
        if (!labels.contains(label))
          (label: label, referenced: false, defined: true),
    ];
  }

  static Set<String> _definitions(String text) => {
    for (final match in _footnoteDefinition.allMatches(text)) match[1]!,
  };

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

final class Relationships {
  const Relationships(this.labels) : malformed = false;

  const Relationships.malformed() : labels = const <String>[], malformed = true;

  final List<String> labels;
  final bool malformed;
}
