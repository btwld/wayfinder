import 'package:path/path.dart' as p;

import '../models/chunk.dart';

/// One passage as the search Markdown prints it: its citation `prefix`,
/// the `bundle` name shown in its bracket, the `bundleRoot` identifying its
/// source decisions, and whether its file changed after indexing.
typedef MarkdownPassage = ({
  String prefix,
  String? bundle,
  String? bundleRoot,
  Chunk chunk,
  String reason,
  String? relationship,
  String? viaPath,
  bool sourceChanged,
});

typedef _PassageKey = (String, String, int, int);

_PassageKey _keyOf(MarkdownPassage passage) => (
  passage.prefix,
  passage.chunk.sourcePath,
  passage.chunk.lineStart,
  passage.chunk.lineEnd,
);

String _escapeControlChars(String value) => value.replaceAllMapped(
  RegExp(r'[\x00-\x08\x0b-\x1f\x7f-\x9f]'),
  (match) =>
      '\\u{${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}}',
);

String _inline(String value, String Function(String) escape) =>
    escape(value.replaceAll(RegExp(r'[\r\n\u2028\u2029]+'), ' ').trim());

List<String> _formatSources(
  Object? rawSources, {
  required String prefix,
  required Map<String, String?> sourcePaths,
  required String sourcePath,
}) {
  if (rawSources is! List) return const [];
  final fullSelfPath = p.posix.normalize('$prefix$sourcePath');
  final seen = <String>{};
  final formatted = <String>[];
  for (final item in rawSources) {
    if (item is! Map) continue;
    if (item['resource'] case final String resource) {
      final trimmed = resource.trim();
      if (trimmed.isEmpty) continue;
      final id = switch (item['id']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      };
      var target = trimmed;
      if (sourcePaths[trimmed] case final display?) {
        final suffixIndex = trimmed.indexOf(RegExp(r'[?#]'));
        final suffix = suffixIndex >= 0 ? trimmed.substring(suffixIndex) : '';
        final resolvedPath = p.posix.normalize('$prefix$display');
        if (resolvedPath == fullSelfPath && suffix.isEmpty) continue;
        target = '$resolvedPath$suffix';
      }
      final entry = id == null ? target : '[$id] $target';
      if (seen.add(entry)) formatted.add(entry);
    }
  }
  return formatted;
}

String? _formatRelation(
  MarkdownPassage passage, {
  required String Function(String) escape,
}) {
  if (passage.reason == 'match' ||
      (passage.viaPath == null && passage.relationship == null)) {
    return null;
  }
  final rel = passage.relationship ?? passage.reason;
  final via = passage.viaPath == null
      ? null
      : '${passage.prefix}${passage.viaPath}';
  return '${_inline(rel, escape)}'
      '${via == null ? '' : ' via ${_inline(via, escape)}'}';
}

String _renderPassage(
  MarkdownPassage passage, {
  required Map<String, String?> sourcePaths,
  required Iterable<String> relations,
  required String Function(String) escape,
}) {
  final chunk = passage.chunk;
  final okf = chunk.metadata['okf'] as Map?;
  final frontmatter = okf?['frontmatter'] as Map?;
  final status = frontmatter?['status']?.toString() ?? 'stable';
  final citation =
      '${_inline('${passage.prefix}${chunk.sourcePath}', escape)}:${chunk.lineStart}-${chunk.lineEnd}';
  final bracket =
      '[${passage.bundle == null ? '' : '${_inline(passage.bundle!, escape)}; '}${_inline(status, escape)}; ${_inline(passage.reason, escape)}${passage.sourceChanged ? '; source changed' : ''}]';
  final lines = <String>['### $citation $bracket'];

  final type = frontmatter?['type']?.toString().trim();
  final title = frontmatter?['title']?.toString().trim();
  final parts = <String>[
    if (type != null && type.isNotEmpty) '**Type:** ${_inline(type, escape)}',
    if (title != null && title.isNotEmpty)
      '**Title:** ${_inline(title, escape)}',
  ];
  if (parts.isNotEmpty) lines.add('- ${parts.join(' | ')}');
  if (okf?['headingPath'] case final List<Object?> headingPath
      when headingPath.isNotEmpty) {
    final section = headingPath
        .map((e) => _inline(e.toString(), escape))
        .join(' > ');
    lines.add('- **Section:** $section');
  }
  if (relations.isNotEmpty) {
    lines.add('- **Relation:** ${relations.join(', ')}');
  }
  final sources = _formatSources(
    frontmatter?['sources'],
    prefix: passage.prefix,
    sourcePaths: sourcePaths,
    sourcePath: chunk.sourcePath,
  );
  if (sources.isNotEmpty) {
    lines.add(
      '- **Sources:** ${sources.map((s) => _inline(s, escape)).join(', ')}',
    );
  }
  lines
    ..add('')
    ..add(escape(chunk.content));
  return lines.join('\n');
}

/// `## Matches` and `## Related Context`, then the notices, with control
/// characters escaped.
String renderSearchMarkdown({
  required List<MarkdownPassage> matches,
  required List<MarkdownPassage> context,
  required List<String> notices,
  Map<String, String?> Function(MarkdownPassage passage)? sourcePaths,
}) {
  const escape = _escapeControlChars;
  final relationsByKey = <_PassageKey, Set<String>>{};
  for (final item in context) {
    if (_formatRelation(item, escape: escape) case final String rel) {
      (relationsByKey[_keyOf(item)] ??= <String>{}).add(rel);
    }
  }
  final matchedKeys = {for (final m in matches) _keyOf(m)};
  final seenRelatedKeys = <_PassageKey>{};
  final related = [
    for (final item in context)
      if (item.reason != 'match' &&
          !matchedKeys.contains(_keyOf(item)) &&
          seenRelatedKeys.add(_keyOf(item)))
        item,
  ];
  final lines = <String>[
    if (matches.isNotEmpty) ...[
      '## Matches',
      '',
      for (final match in matches) ...[
        _renderPassage(
          match,
          sourcePaths: sourcePaths?.call(match) ?? const {},
          relations: relationsByKey[_keyOf(match)] ?? const {},
          escape: escape,
        ),
        '',
      ],
    ],
    if (related.isNotEmpty) ...[
      '## Related Context',
      '',
      for (final item in related) ...[
        _renderPassage(
          item,
          sourcePaths: sourcePaths?.call(item) ?? const {},
          relations: relationsByKey[_keyOf(item)] ?? const {},
          escape: escape,
        ),
        '',
      ],
    ],
    for (final notice in notices) 'Notice: ${_inline(notice, escape)}',
    matches.isEmpty && related.isEmpty
        ? 'No passages found.'
        : 'Ranked passages; verify the cited support before answering.',
  ];
  return lines.join('\n');
}
