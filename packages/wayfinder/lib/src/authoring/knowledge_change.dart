import 'package:collection/collection.dart';
import 'package:okf/okf.dart';

import '../field_edges.dart';

/// One write to a knowledge bundle, which `KnowledgeWriter.prepare` maps
/// onto okf's change set.
///
/// The writer owns a concept's `generated` and `verified` frontmatter: it
/// records them from the write's `KnowledgeStamp`, so a change that names
/// either key is refused with an [ArgumentError].
sealed class KnowledgeChange {
  const KnowledgeChange();
}

/// Creates the concept [id] from [frontmatter] and [body].
final class CreateConcept extends KnowledgeChange {
  CreateConcept({
    required this.id,
    required Map<String, Object?> frontmatter,
    this.body = '',
  }) : frontmatter = Map.unmodifiable(frontmatter);

  final OkfConceptId id;
  final Map<String, Object?> frontmatter;
  final String body;
}

/// Changes the concept [id]. Each [frontmatter] entry replaces that key, and
/// a null value removes it; keys it does not name stay as they are. [body],
/// when given, replaces the body.
///
/// An update with no field and no body changes nothing but what its stamp
/// records, which is how a verification is written.
final class UpdateConcept extends KnowledgeChange {
  UpdateConcept({
    required this.id,
    Map<String, Object?> frontmatter = const {},
    this.body,
  }) : frontmatter = Map.unmodifiable(frontmatter);

  final OkfConceptId id;
  final Map<String, Object?> frontmatter;
  final String? body;

  /// Whether this update changes the content of the concept as it stands
  /// ([current]): [changesConceptContent] of [current] and of [current]
  /// with this update's fields and body applied. `KnowledgeWriter.prepare`
  /// decides with this whether the write records `generated`, on the
  /// concept as it reads it.
  bool changesContent(OkfDocument current) {
    final fields = Map.of(current.frontmatter);
    for (final MapEntry(:key, :value) in frontmatter.entries) {
      if (value == null) {
        fields.remove(key);
      } else {
        fields[key] = value;
      }
    }
    return changesConceptContent(
      current,
      current.copyWith(frontmatter: fields, body: body),
    );
  }
}

/// Whether [after] changes the content of the concept [before]: its body,
/// `title`, `description` or `type`, the content a `generated` stamp dates
/// (OKF 0.2 §5.2). [before] is null for a concept a write creates, whose
/// content is always new.
///
/// A field changes when its value differs by deep equality, including one
/// that appears or is removed. Bodies compare as okf writes them, so a
/// difference okf's serialization removes, such as line endings or a
/// missing final newline, changes nothing. No other field, such as
/// `status`, `tags`, `relationships`, `generated` or `verified`, is
/// content.
///
/// `KnowledgeWriter.prepare` records `generated` exactly when the write
/// creates a concept or this holds for the one it updates, and
/// `KnowledgeContentLog` records its entry on the same rule; a link, a
/// deprecation and `RegenerateIndexes` change no content.
bool changesConceptContent(OkfDocument? before, OkfDocument after) {
  if (before == null) return true;
  for (final key in _contentFields) {
    if (!const DeepCollectionEquality().equals(
      before.frontmatter[key],
      after.frontmatter[key],
    )) {
      return true;
    }
  }
  String canonical(String text) =>
      OkfDocument(body: text, hasFrontmatter: false).serialize();
  return canonical(before.body) != canonical(after.body);
}

/// The frontmatter fields that are a concept's content, beside its body.
const _contentFields = ['type', 'title', 'description'];

/// Appends [relationship] to the `relationships` field of [source] (guide
/// §5.5), unless an entry with the same name and resource is there already.
final class LinkConcepts extends KnowledgeChange {
  const LinkConcepts({required this.source, required this.relationship});

  final OkfConceptId source;
  final KnowledgeRelationship relationship;
}

/// Sets the `status` of the concept [id] to `deprecated` and appends
/// [relationships] to its `relationships` field, such as one that names its
/// replacement. [note] goes into okf's lifecycle log entry.
final class DeprecateConcept extends KnowledgeChange {
  DeprecateConcept({
    required this.id,
    this.note,
    Iterable<KnowledgeRelationship> relationships = const [],
  }) : relationships = List.unmodifiable(relationships);

  final OkfConceptId id;
  final String? note;
  final List<KnowledgeRelationship> relationships;
}

/// The repair: writes each file the selected Profile's fixable rules
/// generate whose text differs, exactly what `wayfinder validate --fix`
/// writes, and changes no concept.
final class RegenerateIndexes extends KnowledgeChange {
  const RegenerateIndexes();
}

/// One entry of a concept's `relationships` field.
final class KnowledgeRelationship {
  const KnowledgeRelationship({
    required this.relationship,
    required this.resource,
  });

  /// A relationship to the concept [target], written as its bundle-relative
  /// path with each segment percent-encoded, such as
  /// `/reporting/pdf-export.md`.
  KnowledgeRelationship.toConcept({
    required String relationship,
    required OkfConceptId target,
  }) : this(
         relationship: relationship,
         resource: '/${_encodeLinkPath(target.documentPath)}',
       );

  /// The relationship's name.
  final String relationship;

  /// What the relationship points at: a bundle path or a URI.
  final String resource;

  bool sameAs(Object? entry) =>
      entry is Map &&
      entry[relationshipsLinkField.nameKey] == relationship &&
      entry['resource'] == resource;

  Map<String, Object?> toJson() => {
    relationshipsLinkField.nameKey: relationship,
    'resource': resource,
  };
}

/// Encodes each segment as okf writes a link path: `Uri.encodeComponent`,
/// with parentheses encoded too, since a raw `)` ends a Markdown
/// destination.
String _encodeLinkPath(String path) => path
    .split('/')
    .map(
      (segment) => Uri.encodeComponent(
        segment,
      ).replaceAll('(', '%28').replaceAll(')', '%29'),
    )
    .join('/');
