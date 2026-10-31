import 'package:markdown/markdown.dart' as markdown;

final class ParsedBody {
  ParsedBody(String source) {
    nodes = _document.parse(source);
  }

  final _document = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
  );
  late final List<markdown.Node> nodes;

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

  /// The parser retains definitions even when no reference joined them.
  /// Read unjoined references from text nodes, including adjacent references,
  /// while leaving code and rendered footnote bodies out of the scan.
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
            final label = Uri.decodeComponent(href.substring(4));
            labels.add(label);
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
    final defined = _document.footnoteReferences.keys.toSet();
    return [
      for (final label in labels)
        (label: label, referenced: true, defined: defined.contains(label)),
      for (final label in defined)
        if (!labels.contains(label))
          (label: label, referenced: false, defined: true),
    ];
  }
}

final RegExp _footnoteReference = RegExp(r'\[\^([^\]]+)\]');
