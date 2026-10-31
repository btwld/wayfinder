import 'package:okf/okf.dart';

/// Deterministic frontmatter eligibility, independent of retrieval scores.
/// Values within each set use OR, except [requiredTags], which uses AND.
/// Different fields combine with AND. Identifiers are exact and case-sensitive;
/// title/description containment is literal and case-insensitive.
class KnowledgeMetadataFilter {
  KnowledgeMetadataFilter({
    Set<String> tags = const {},
    Set<String> requiredTags = const {},
    Set<String> types = const {},
    Set<String> statuses = const {},
    Set<String> pathPrefixes = const {},
    this.titleContains,
    this.descriptionContains,
  }) : tags = Set.unmodifiable(tags),
       requiredTags = Set.unmodifiable(requiredTags),
       types = Set.unmodifiable(types),
       statuses = Set.unmodifiable(statuses),
       pathPrefixes = Set.unmodifiable(pathPrefixes) {
    for (final value in [
      ...tags,
      ...requiredTags,
      ...types,
      ...statuses,
      ...pathPrefixes,
      ?titleContains,
      ?descriptionContains,
    ]) {
      if (value.trim().isEmpty) {
        throw ArgumentError('Metadata filter values must not be blank.');
      }
    }
  }

  final Set<String> tags;
  final Set<String> requiredTags;
  final Set<String> types;
  final Set<String> statuses;
  final Set<String> pathPrefixes;
  final String? titleContains;
  final String? descriptionContains;

  bool allows(Map<String, Object?> raw, String path) {
    final rawTags = raw['tags'];
    final documentTags = rawTags is List
        ? rawTags.whereType<String>().toSet()
        : <String>{};
    // OKF defines the absent lifecycle status as stable. Keep producer-defined
    // values intact rather than collapsing all custom values to `unknown`.
    final status = raw.containsKey('status') ? raw['status'] : 'stable';
    bool contains(Object? value, String? query) =>
        query == null ||
        (value is String && value.toLowerCase().contains(query.toLowerCase()));
    return (tags.isEmpty || tags.any(documentTags.contains)) &&
        requiredTags.every(documentTags.contains) &&
        (types.isEmpty || types.contains(raw['type'])) &&
        (statuses.isEmpty || statuses.contains(status)) &&
        (pathPrefixes.isEmpty ||
            pathPrefixes.any(OkfConceptId.fromDocumentPath(path).isWithin)) &&
        contains(raw['title'], titleContains) &&
        contains(raw['description'], descriptionContains);
  }
}
