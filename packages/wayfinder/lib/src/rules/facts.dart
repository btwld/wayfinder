import 'package:okf/okf_io.dart';

import '../finding_helpers.dart';
import '../profile_context.dart';

/// The closed set of record kinds a rule may check. Adding a kind is an
/// engine release; a catalog naming an unknown kind is rejected at load.
enum SubjectKind {
  /// One concept's authored frontmatter as plain JSON. Its shape is open, so
  /// a rule may name any key.
  frontmatter(facts: null),

  /// One concept's derived facts.
  concept(facts: {'path', 'type', 'keys', 'tags', 'source_ids'}),

  /// One distinct actor id used anywhere in the bundle, located at the
  /// first concept that uses it.
  actor(facts: {'id', 'first_use'});

  const SubjectKind({required this.facts});

  /// The fact names every subject of this kind carries, or null when the
  /// shape is open.
  final Set<String>? facts;

  /// The location keys a rule may report at.
  Set<String> get locations => const {'self'};
}

/// One record a rule can check. [facts] is plain JSON; [locations] maps the
/// kind's location keys to bundle-relative paths.
final class Subject {
  const Subject(this.kind, this.facts, this.locations);

  final SubjectKind kind;
  final Map<String, Object?> facts;
  final Map<String, String> locations;
}

/// The bundle parsed once, shared by every rule. Subjects are built here, in
/// `loaded.documents` order, and every join (actor first use, tag counts)
/// happens here so rules never parse.
final class BundleFacts {
  BundleFacts.project(this.loaded, {required this.context})
    : _subjects = {
        SubjectKind.frontmatter: [
          for (final MapEntry(key: path, value: document)
              in loaded.documents.entries)
            Subject(
              SubjectKind.frontmatter,
              _json(document.frontmatter) as Map<String, Object?>,
              {'self': path},
            ),
        ],
        SubjectKind.concept: [
          for (final MapEntry(key: path, value: document)
              in loaded.documents.entries)
            Subject(SubjectKind.concept, _concept(path, document), {
              'self': path,
            }),
        ],
        SubjectKind.actor: _actors(loaded),
      };

  final OkfBundleLoadResult loaded;
  final ProfileValidationContext context;
  final Map<SubjectKind, List<Subject>> _subjects;
  final _derived = <String, Object?>{};

  Iterable<Subject> of(SubjectKind kind) => _subjects[kind]!;

  /// A per-validation memo for derived data several builtins share, such as
  /// parsed bodies or the link graph, computed on first use.
  T derive<T>(String key, T Function() compute) =>
      _derived.putIfAbsent(key, compute) as T;
}

Map<String, Object?> _concept(String path, OkfDocument document) {
  final counts = <String, int>{};
  for (final tag in document.tags) {
    counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
  }
  return {
    'path': path,
    'type': document.type,
    'keys': document.frontmatter.keys.toList(),
    'tags': [
      for (final tag in document.tags) {'value': tag, 'count': counts[tag]},
    ],
    'source_ids': document.metadata.sources
        .map((source) => source.id)
        .nonNulls
        .toList(),
  };
}

List<Subject> _actors(OkfBundleLoadResult loaded) {
  final firstUse = <String, String>{};
  for (final MapEntry(key: path, value: document) in loaded.documents.entries) {
    for (final actor in actorIds(document)) {
      firstUse.putIfAbsent(actor, () => path);
    }
  }
  return [
    for (final MapEntry(key: id, value: path) in firstUse.entries)
      Subject(SubjectKind.actor, {'id': id, 'first_use': path}, {'self': path}),
  ];
}

/// The actor ids a concept's frontmatter uses, in field order.
Iterable<String> actorIds(OkfDocument document) sync* {
  final generated = document.frontmatter['generated'];
  if (generated is Map<Object?, Object?>) {
    final actor = nonEmptyString(generated['by']);
    if (actor != null) yield actor;
  }
  final verified = document.frontmatter['verified'];
  final events = verified is List ? verified : <Object?>[verified];
  for (final event in events.whereType<Map<Object?, Object?>>()) {
    if (nonEmptyString(event['by']) case final actor?) yield actor;
  }
  final sources = document.frontmatter['sources'];
  if (sources is List) {
    for (final source in sources.whereType<Map<Object?, Object?>>()) {
      if (nonEmptyString(source['author']) case final actor?) yield actor;
    }
  }
}

/// YAML values as the JSON the predicate evaluates: string keys, lists,
/// scalars. Anything else renders as its string form.
Object? _json(Object? value) => switch (value) {
  Map() => {
    for (final MapEntry(:key, value: nested) in value.entries)
      '$key': _json(nested),
  },
  Iterable() => [for (final item in value) _json(item)],
  null || String() || num() || bool() => value,
  _ => '$value',
};
