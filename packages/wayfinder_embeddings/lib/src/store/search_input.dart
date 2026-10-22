import 'package:ack/ack.dart';

import '../okf/knowledge_index.dart';

// Include Unicode NEXT LINE, which Dart's trim treats as whitespace.
const _nonBlank = r'[^\s\u0085]';

/// The search a host tool accepts, as JSON: a `query` with a non-blank
/// character and an optional `limit` from 1 to 100 (default 5). The CLI
/// converts its arguments to numbers before parsing them with it.
final wayfinderSearchInput = Ack.object({
  'query': Ack.string()
      .minLength(1)
      .matches(
        _nonBlank,
        message: 'Query must contain non-whitespace characters.',
      ),
  'limit': Ack.integer().min(1).max(100).optional().withDefault(5),
});

AckSchema<String, String> _value() => Ack.string()
    .minLength(1)
    .matches(_nonBlank, message: 'Metadata filter values must not be blank.');

/// The frontmatter filters a host tool accepts, as JSON, with the meaning of
/// [KnowledgeMetadataFilter]: optional `tags`, `require_tags`, `types`,
/// `statuses` and `path_prefixes` lists, and `title_contains` and
/// `description_contains` strings. Convert a parsed value with
/// [knowledgeMetadataFilterFromInput].
final knowledgeMetadataFilterInput = Ack.object({
  'tags': Ack.list(_value()).unique().optional(),
  'require_tags': Ack.list(_value()).unique().optional(),
  'types': Ack.list(_value()).unique().optional(),
  'statuses': Ack.list(_value()).unique().optional(),
  'path_prefixes': Ack.list(_value()).unique().optional(),
  'title_contains': _value().optional(),
  'description_contains': _value().optional(),
});

/// The [KnowledgeMetadataFilter] a value [knowledgeMetadataFilterInput]
/// parsed describes; absent keys filter nothing.
KnowledgeMetadataFilter knowledgeMetadataFilterFromInput(
  Map<String, Object?> input,
) {
  Set<String> values(String key) => {
    ...?(input[key] as List<Object?>?)?.cast<String>(),
  };
  return KnowledgeMetadataFilter(
    tags: values('tags'),
    requiredTags: values('require_tags'),
    types: values('types'),
    statuses: values('statuses'),
    pathPrefixes: values('path_prefixes'),
    titleContains: input['title_contains'] as String?,
    descriptionContains: input['description_contains'] as String?,
  );
}
