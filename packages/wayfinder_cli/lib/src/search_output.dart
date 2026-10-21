import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'project_search.dart';

typedef _MarkdownPassage = ({
  String prefix,
  String? bundle,
  String? bundleRoot,
  Chunk chunk,
  String reason,
  String? relationship,
  String? viaPath,
});

typedef _PassageKey = (String, String, int, int);

_PassageKey _keyOf(_MarkdownPassage passage) => (
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

final _uriSchemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');
final _proseSignalPattern = RegExp(r'[`\s]');
final _knownFileExtensionPattern = RegExp(
  r'\.(?:md|markdown|txt|pdf|docx?|xlsx?|pptx?|csv|tsv|json|ya?ml|html?|xml|sql|py|dart|ts|js|sh|png|jpe?g|webp|svg|zip|parquet)$',
  caseSensitive: false,
);

bool _isResolvablePath(
  String rawPath, {
  required String? bundleRoot,
  required String sourcePath,
}) {
  if (rawPath.isEmpty) return true;
  if (rawPath.contains('`') || rawPath.startsWith('//')) return false;
  if (rawPath.startsWith('/') ||
      rawPath.startsWith('./') ||
      rawPath.startsWith('../')) {
    return true;
  }
  if (bundleRoot != null) {
    final docDir = p.posix.dirname(sourcePath);
    final relative = docDir == '.' ? rawPath : p.posix.join(docDir, rawPath);
    final segments = p.posix.split(relative).map((segment) {
      try {
        return Uri.decodeComponent(segment);
      } on Object {
        return segment;
      }
    });
    final candidate = p.normalize(p.joinAll([bundleRoot, ...segments]));
    if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
      return true;
    }
  }
  final hasWhitespace = _proseSignalPattern.hasMatch(rawPath);
  final slashIndex = rawPath.indexOf('/');
  if (slashIndex > 0) {
    return !_proseSignalPattern.hasMatch(rawPath.substring(0, slashIndex)) &&
        _knownFileExtensionPattern.hasMatch(rawPath);
  }
  return !hasWhitespace && _knownFileExtensionPattern.hasMatch(rawPath);
}

List<String> _formatSources(
  Object? rawSources, {
  required String prefix,
  required String? bundleRoot,
  required String sourcePath,
}) {
  if (rawSources is! List) return const [];
  final fullSelfPath = p.posix.normalize('$prefix$sourcePath');
  final docDir = p.posix.dirname(fullSelfPath);
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
      String formatEntry(String target) =>
          id == null ? target : '[$id] $target';
      final suffixIndex = trimmed.indexOf(RegExp(r'[?#]'));
      final rawPath = suffixIndex >= 0
          ? trimmed.substring(0, suffixIndex)
          : trimmed;
      final suffix = suffixIndex >= 0 ? trimmed.substring(suffixIndex) : '';
      if (_uriSchemePattern.hasMatch(trimmed) ||
          trimmed.startsWith('//') ||
          !_isResolvablePath(
            rawPath,
            bundleRoot: bundleRoot,
            sourcePath: sourcePath,
          )) {
        final entry = formatEntry(trimmed);
        if (seen.add(entry)) {
          formatted.add(entry);
        }
        continue;
      }
      final resolvedPath = rawPath.isEmpty
          ? fullSelfPath
          : rawPath.startsWith('/')
          ? p.posix.normalize('$prefix${rawPath.substring(1)}')
          : p.posix.normalize(
              docDir == '.' ? rawPath : p.posix.join(docDir, rawPath),
            );
      if (resolvedPath == fullSelfPath && suffix.isEmpty) {
        continue;
      }
      final entry = formatEntry('$resolvedPath$suffix');
      if (seen.add(entry)) {
        formatted.add(entry);
      }
    }
  }
  return formatted;
}

String? _formatRelation(
  _MarkdownPassage passage, {
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
  _MarkdownPassage passage, {
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
      '[${passage.bundle == null ? '' : '${_inline(passage.bundle!, escape)}; '}${_inline(status, escape)}; ${_inline(passage.reason, escape)}]';
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
    bundleRoot: passage.bundleRoot,
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

String _renderSearchMarkdown({
  required List<_MarkdownPassage> matches,
  required List<_MarkdownPassage> context,
  required List<String> notices,
  required String Function(String) escape,
}) {
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

/// Formats a single-bundle search response as clean Markdown with
/// `## Matches` and `## Related Context`.
String formatSearchMarkdown(
  KnowledgeSearchResponse result, {
  String prefix = '',
  String? bundle,
  String? bundleRoot,
  String Function(String) escape = _escapeControlChars,
}) => _renderSearchMarkdown(
  matches: [
    for (final hit in result.matches)
      (
        prefix: prefix,
        bundle: bundle,
        bundleRoot: bundleRoot,
        chunk: hit.chunk,
        reason: 'match',
        relationship: null,
        viaPath: null,
      ),
  ],
  context: [
    for (final hit in result.context)
      (
        prefix: prefix,
        bundle: bundle,
        bundleRoot: bundleRoot,
        chunk: hit.result.chunk,
        reason: hit.reason,
        relationship: hit.fieldEdge?.name,
        viaPath: hit.viaPath,
      ),
  ],
  notices: result.notices,
  escape: escape,
);

/// Formats a multi-bundle project search response as clean Markdown with
/// `## Matches` and `## Related Context`.
String formatProjectSearchMarkdown(
  ProjectSearchResult result, {
  String Function(String) escape = _escapeControlChars,
}) => _renderSearchMarkdown(
  matches: [
    for (final match in result.matches)
      (
        prefix: '${match.bundle.path}/',
        bundle: match.bundle.name,
        bundleRoot: match.bundle.root,
        chunk: match.hit.chunk,
        reason: 'match',
        relationship: null,
        viaPath: null,
      ),
  ],
  context: [
    for (final entry in result.context)
      (
        prefix: '${entry.bundle.path}/',
        bundle: entry.bundle.name,
        bundleRoot: entry.bundle.root,
        chunk: entry.hit.result.chunk,
        reason: entry.hit.reason,
        relationship: entry.hit.fieldEdge?.name,
        viaPath: entry.hit.viaPath,
      ),
  ],
  notices: result.notices,
  escape: escape,
);

/// The shared CLI JSON representation preserves original citations and metadata.
Map<String, Object?> searchOutput(KnowledgeSearchResponse result) => {
  'context': [
    for (final hit in result.context)
      {
        'chunk': hit.result.chunk.toMap(),
        'similarity': hit.result.similarity,
        'reason': hit.reason,
        'viaPath': ?hit.viaPath,
        'relationship': ?hit.fieldEdge?.name,
      },
  ],
  'matches': [
    for (final hit in result.matches)
      {'chunk': hit.chunk.toMap(), 'similarity': hit.similarity},
  ],
  'notices': result.notices,
};
