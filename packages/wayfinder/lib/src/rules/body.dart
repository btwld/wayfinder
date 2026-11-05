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
      if (node case markdown.Element(tag: 'h1', :final textContent))
        textContent,
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
    final defined = {
      for (final match in _footnoteDefinition.allMatches(
        source.replaceAll(_fencedCode, ''),
      ))
        match[1]!,
    };
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
