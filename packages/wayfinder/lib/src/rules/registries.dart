import 'package:collection/collection.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';

/// The 2026.2 in-bundle registries, `types.md` and `actors.md`, read from
/// their first Markdown table.
final class LegacyRegistries {
  LegacyRegistries(this.loaded);

  final OkfBundleLoadResult loaded;

  late final Registry types = _registry(loaded.documents['types.md'], const [
    'Type',
    'Intended content',
  ]);

  late final Registry actors = _registry(loaded.documents['actors.md'], const [
    'Actor ID',
    'Name',
    'Organization',
    'Side',
    'Role',
    'Active',
  ]);
}

/// A registry concept and its rows; [rows] is null when the concept is
/// absent or its table header is not the registry's.
final class Registry {
  const Registry(this.document, this.rows);

  final OkfDocument? document;
  final List<List<String>>? rows;
}

Registry _registry(OkfDocument? document, List<String> header) {
  if (document == null) return const Registry(null, null);
  final table = _firstTable(document.body);
  if (table == null ||
      !const ListEquality<String>().equals(table.header, header)) {
    return Registry(document, null);
  }
  return Registry(
    document,
    table.rows.where((row) => row.length == header.length).toList(),
  );
}

final class _MarkdownTable {
  const _MarkdownTable(this.header, this.rows);

  final List<String> header;
  final List<List<String>> rows;
}

_MarkdownTable? _firstTable(String body) {
  final nodes = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
  ).parse(body);
  final table = nodes
      .whereType<markdown.Element>()
      .where((element) => element.tag == 'table')
      .firstOrNull;
  if (table == null) return null;
  final sections = table.children?.whereType<markdown.Element>().toList() ?? [];
  final head = sections.where((element) => element.tag == 'thead').firstOrNull;
  final tableBody = sections
      .where((element) => element.tag == 'tbody')
      .firstOrNull;
  if (head == null) return null;
  final header = _tableRows(head).singleOrNull;
  if (header == null) return null;
  return _MarkdownTable(header, tableBody == null ? [] : _tableRows(tableBody));
}

List<List<String>> _tableRows(markdown.Element section) =>
    (section.children ?? const <markdown.Node>[])
        .whereType<markdown.Element>()
        .where((element) => element.tag == 'tr')
        .map(
          (row) => (row.children ?? const <markdown.Node>[])
              .whereType<markdown.Element>()
              .map((cell) => cell.textContent.trim())
              .toList(),
        )
        .toList();
