import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import 'cancellation.dart';
import 'exception.dart';
import 'metadata_filter.dart';
import 'project_bundles.dart';

/// Project query columns. Identity is always returned separately.
const wayfinderQueryColumns = [
  'title',
  'description',
  'type',
  'status',
  'effective_status',
  'tags',
  'resource',
];
const wayfinderQuerySortFields = [
  'title',
  'type',
  'effective_status',
  'id',
  'path',
];

/// A deterministic, read-only selection of whole OKF concepts, not passages.
/// JSON is the same contract used by saved definitions, CLI and MCP.
final class WayfinderQuery {
  WayfinderQuery._(
    this._json,
    this.filter,
    this.select,
    this.orderBy,
    this.groupBy,
  );

  factory WayfinderQuery.fromJson(Map<String, Object?> json) {
    _keys(json, {'where', 'select', 'order_by', 'group_by'});
    final where = _object(
      json.containsKey('where') ? json['where'] : <String, Object?>{},
      'where',
    );
    _keys(where, {
      'types',
      'tags',
      'required_tags',
      'statuses',
      'path_prefixes',
      'title_contains',
      'description_contains',
    });
    List<String> strings(String key) {
      if (!where.containsKey(key)) return const [];
      return _strings(where[key], key);
    }

    final filter = KnowledgeMetadataFilter(
      types: strings('types').toSet(),
      tags: strings('tags').toSet(),
      requiredTags: strings('required_tags').toSet(),
      statuses: strings('statuses').toSet(),
      pathPrefixes: strings('path_prefixes').toSet(),
      titleContains: _optionalString(where, 'title_contains'),
      descriptionContains: _optionalString(where, 'description_contains'),
    );
    final group = _optionalString(json, 'group_by');
    if (group != null && !const ['type', 'effective_status'].contains(group)) {
      _invalid('group_by must be type or effective_status.');
    }
    if (group != null &&
        (json.containsKey('select') || json.containsKey('order_by'))) {
      _invalid('Grouped queries do not accept select or order_by.');
    }
    final select = json.containsKey('select')
        ? _strings(json['select'], 'select')
        : const ['title', 'type', 'effective_status'];
    if (select.isEmpty ||
        select.any((field) => !wayfinderQueryColumns.contains(field))) {
      _invalid('select must name supported columns.');
    }
    final order = <({String field, bool descending})>[];
    if (json.containsKey('order_by')) {
      if (json['order_by'] is! List) _invalid('order_by must be a list.');
      for (final entry in json['order_by']! as List) {
        final item = _object(entry, 'order_by entry');
        _keys(item, {'field', 'direction'});
        final field = _optionalString(item, 'field');
        final direction = _optionalString(item, 'direction') ?? 'asc';
        if (!wayfinderQuerySortFields.contains(field) ||
            !const ['asc', 'desc'].contains(direction)) {
          _invalid('Unsupported order_by field or direction.');
        }
        order.add((field: field!, descending: direction == 'desc'));
      }
    }
    final normalized = <String, Object?>{
      'where': {
        if (filter.types.isNotEmpty) 'types': filter.types.toList()..sort(),
        if (filter.tags.isNotEmpty) 'tags': filter.tags.toList()..sort(),
        if (filter.requiredTags.isNotEmpty)
          'required_tags': filter.requiredTags.toList()..sort(),
        if (filter.statuses.isNotEmpty)
          'statuses': filter.statuses.toList()..sort(),
        if (filter.pathPrefixes.isNotEmpty)
          'path_prefixes': filter.pathPrefixes.toList()..sort(),
        if (filter.titleContains != null)
          'title_contains': filter.titleContains,
        if (filter.descriptionContains != null)
          'description_contains': filter.descriptionContains,
      },
      if (group == null) 'select': select,
      if (group == null)
        'order_by': [
          for (final item in order)
            {
              'field': item.field,
              'direction': item.descending ? 'desc' : 'asc',
            },
        ],
      'group_by': ?group,
    };
    // Own every collection; callers cannot change the query after validation.
    return WayfinderQuery._(
      jsonEncode(normalized),
      filter,
      List.unmodifiable(select),
      List.unmodifiable(order),
      group,
    );
  }

  final String _json;
  final KnowledgeMetadataFilter filter;
  final List<String> select;
  final List<({String field, bool descending})> orderBy;
  final String? groupBy;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;
}

/// Source load findings refuse the entire result, rather than returning partial rows.
final class WayfinderQueryRefused extends WayfinderException {
  WayfinderQueryRefused(this.report) : super('query-refused', report.toText());
  final OkfReport report;
}

/// Versioned table/group data; no source body is copied into the result.
final class WayfinderQueryResult {
  WayfinderQueryResult._(Map<String, Object?> value)
    : _json = jsonEncode(value);
  final String _json;
  Map<String, Object?> toJson() => jsonDecode(_json) as Map<String, Object?>;

  /// Markdown-friendly text with explicit pagination and escaped cell values.
  String toText() {
    final data = toJson();
    final groups = data['kind'] == 'groups';
    final rows = (data[groups ? 'groups' : 'rows']! as List)
        .cast<Map<String, Object?>>();
    final select = groups
        ? ['key', 'count']
        : [
            'bundle',
            'id',
            ...((data['query']! as Map)['select']! as List).cast<String>(),
          ];
    String cell(Object? value) {
      final text = value == null
          ? ''
          : value is String
          ? value
          : jsonEncode(value);
      return text.runes.map((r) {
        if (r < 32 || (r >= 127 && r <= 159)) {
          return '\\u{${r.toRadixString(16)}}';
        }
        return switch (r) {
          38 => '&amp;',
          60 => '&lt;',
          62 => '&gt;',
          124 => '&#124;',
          91 => '&#91;',
          93 => '&#93;',
          96 => '&#96;',
          42 => '&#42;',
          95 => '&#95;',
          92 => '&#92;',
          _ => String.fromCharCode(r),
        };
      }).join();
    }

    return [
      '${data['returned']} of ${groups ? data['group_total'] : data['total']} ${groups ? 'groups' : 'concepts'}; offset ${data['offset']}; more: ${data['has_more']}.',
      if (groups) 'Matching concepts: ${data['total']}.',
      '| ${select.join(' | ')} |',
      '| ${select.map((_) => '---').join(' | ')} |',
      for (final row in rows)
        '| ${select.map((key) => cell(groups || key == 'bundle' || key == 'id' ? row[key] : (row['values']! as Map)[key])).join(' | ')} |',
    ].join('\n');
  }
}

/// Queries live files in [bundles], refusing partial reads and observed edits.
/// This is not a transactional filesystem snapshot. No index, model, Profile
/// resolver, network service or computation executor is opened.
Future<WayfinderQueryResult> queryWayfinderBundles(
  List<ProjectBundle> bundles,
  WayfinderQuery query, {
  int offset = 0,
  int limit = 100,
  WayfinderCancellation? cancel,
}) async {
  if (offset < 0 || limit < 1 || limit > 1000) {
    _invalid('offset must be nonnegative and limit must be 1–1000.');
  }
  final rows =
      <({ProjectBundle bundle, String path, Map<String, Object?> metadata})>[];
  final observed = <({ProjectBundle bundle, String fingerprint})>[];
  final identities = <String>{};
  for (final bundle in bundles) {
    throwIfCancelled(cancel);
    if (!identities.add(bundle.path)) _invalid('Bundle paths must be unique.');
    final before = await _fingerprint(bundle.root, cancel);
    final loaded = await const OkfBundleLoader().inspect(bundle.root);
    if (loaded.hasFindings) throw WayfinderQueryRefused(loaded.report);
    final validation = loaded.validate();
    if (!validation.isConformant) {
      throw WayfinderQueryRefused(validation.report);
    }
    observed.add((bundle: bundle, fingerprint: before));
    for (final entry in loaded.documents.entries) {
      throwIfCancelled(cancel);
      final metadata = entry.value.frontmatter;
      if (query.filter.allows(metadata, entry.key)) {
        rows.add((bundle: bundle, path: entry.key, metadata: metadata));
      }
    }
  }
  for (final entry in observed) {
    if (await _fingerprint(entry.bundle.root, cancel) != entry.fingerprint) {
      throw const WayfinderException(
        'query-source-changed',
        'Source files changed during the query; retry.',
      );
    }
  }
  throwIfCancelled(cancel);
  Object? value(Map<String, Object?> raw, String field) =>
      field == 'effective_status'
      ? (raw.containsKey('status') ? raw['status'] : 'stable')
      : raw[field];
  int compare(Object? a, Object? b, bool desc) {
    if (a is! String) return b is String ? 1 : 0;
    if (b is! String) return -1;
    final result = a.compareTo(b);
    return desc ? -result : result;
  }

  rows.sort((a, b) {
    for (final order in query.orderBy) {
      final left = switch (order.field) {
        'id' => OkfConceptId.fromDocumentPath(a.path).value,
        'path' => a.path,
        _ => value(a.metadata, order.field),
      };
      final right = switch (order.field) {
        'id' => OkfConceptId.fromDocumentPath(b.path).value,
        'path' => b.path,
        _ => value(b.metadata, order.field),
      };
      final result = compare(left, right, order.descending);
      if (result != 0) return result;
    }
    final bundleOrder = a.bundle.path.compareTo(b.bundle.path);
    return bundleOrder != 0
        ? bundleOrder
        : OkfConceptId.fromDocumentPath(
            a.path,
          ).value.compareTo(OkfConceptId.fromDocumentPath(b.path).value);
  });
  final grouped = query.groupBy != null;
  final output = <Map<String, Object?>>[];
  if (grouped) {
    final counts = <String?, int>{};
    for (final row in rows) {
      final raw = value(row.metadata, query.groupBy!);
      final key = raw is String ? raw : null;
      counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    final keys = counts.keys.toList()..sort((a, b) => compare(a, b, false));
    output.addAll([
      for (final key in keys) {'key': key, 'count': counts[key]},
    ]);
  } else {
    output.addAll([
      for (final row in rows)
        {
          'bundle': row.bundle.path,
          'id': OkfConceptId.fromDocumentPath(row.path).value,
          'path': row.path,
          'values': {
            for (final field in query.select) field: value(row.metadata, field),
          },
        },
    ]);
  }
  final conversion = _QueryJson();
  final page = [
    for (final row in output.skip(offset).take(limit)) conversion.convert(row),
  ];
  return WayfinderQueryResult._({
    'schema_version': '1',
    'kind': grouped ? 'groups' : 'rows',
    'query': query.toJson(),
    'bundles': [for (final bundle in bundles) bundle.toJson()],
    'total': rows.length,
    if (grouped) 'group_total': output.length,
    'offset': offset,
    'returned': page.length,
    'has_more': offset + page.length < output.length,
    grouped ? 'groups' : 'rows': page,
  });
}

/// Selects exactly one explicit bundle, or the project's configured scope.
Future<List<ProjectBundle>> discoverWayfinderQueryBundles(
  Directory workingDirectory, {
  String? explicitPath,
  String? bundleName,
}) async {
  if (explicitPath != null && bundleName != null) {
    _invalid('Use an explicit path or bundle name, not both.');
  }
  if (explicitPath == null) {
    return (await WayfinderProject.discover(
      workingDirectory,
      bundleName: bundleName,
      searchAncestors: true,
    )).bundles;
  }
  final root = await Directory(
    p.absolute(p.join(workingDirectory.path, explicitPath)),
  ).resolveSymbolicLinks();
  final prefix = await explicitBundlePrefix(workingDirectory, root);
  return [
    ProjectBundle(
      p.basename(root),
      prefix.isEmpty
          ? p.basename(root)
          : prefix.substring(0, prefix.length - 1),
      root,
    ),
  ];
}

// Serialize selected page values only. YAML aliases can share collections;
// JSON cannot, so bound the expanded representation, not only source nodes.
final class _QueryJson {
  int _nodes = 100000;
  int _characters = 4 * 1024 * 1024;

  Object? convert(Object? value, [int depth = 0]) {
    if (--_nodes < 0 || depth > 64) _limit();
    if (value is String) {
      _characters -= value.length;
      if (_characters < 0) _limit();
      return value;
    }
    if (value is DateTime) return convert(value.toIso8601String(), depth);
    if (value is num && !value.isFinite) {
      throw const WayfinderException(
        'query-metadata-invalid',
        'Selected metadata contains a nonfinite number.',
      );
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const WayfinderException(
            'query-metadata-invalid',
            'Selected metadata contains a non-string map key.',
          );
        }
        final key = convert(entry.key, depth + 1) as String;
        result[key] = convert(entry.value, depth + 1);
      }
      return result;
    }
    if (value is List) {
      return [for (final item in value) convert(item, depth + 1)];
    }
    return value;
  }

  Never _limit() => throw const WayfinderException(
    'query-metadata-limit',
    'Selected query page exceeds the metadata expansion limit; narrow its columns or page size.',
  );
}

Future<String> _fingerprint(String root, WayfinderCancellation? cancel) async {
  // Only Markdown affects a concept query. Symlinks are inventory entries but
  // are never followed, matching the OKF loader's traversal policy.
  final entries = await Directory(
    root,
  ).list(recursive: true, followLinks: false).toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  final values = <Object?>[];
  for (final entry in entries) {
    throwIfCancelled(cancel);
    if (entry is Link) {
      values.add([entry.path, 'link', await entry.target()]);
    }
    if (entry is File && entry.path.endsWith('.md')) {
      values.add([
        entry.path,
        sha256.convert(await entry.readAsBytes()).toString(),
      ]);
    }
  }
  return jsonEncode(values);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) _invalid('$name must be an object.');
  return value;
}

void _keys(Map<String, Object?> value, Set<String> keys) {
  for (final key in value.keys) {
    if (!keys.contains(key)) _invalid('Unsupported query key: $key.');
  }
}

List<String> _strings(Object? value, String name) {
  if (value is! List || value.any((e) => e is! String || e.trim().isEmpty)) {
    _invalid('$name must contain nonblank strings.');
  }
  final result = value.cast<String>().toList();
  if (result.toSet().length != result.length) {
    _invalid('$name contains duplicates.');
  }
  return result;
}

String? _optionalString(Map<String, Object?> value, String name) {
  if (!value.containsKey(name)) return null;
  final raw = value[name];
  if (raw is! String || raw.trim().isEmpty) {
    _invalid('$name must be a nonblank string.');
  }
  return raw;
}

Never _invalid(String message) =>
    throw WayfinderException('query-invalid', message);
