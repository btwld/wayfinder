import 'package:ack/ack.dart';

import 'query.dart';

final _strings = Ack.list(Ack.string().minLength(1)).unique();

/// Closed MCP/JSON input; semantic constraints are checked by the same query
/// parser as Dart and CLI. Exactly one query or saved ID is required.
final wayfinderQueryInput = Ack.object({
  'query': Ack.object({
    'where': Ack.object({
      'types': _strings.optional(),
      'tags': _strings.optional(),
      'required_tags': _strings.optional(),
      'statuses': _strings.optional(),
      'path_prefixes': _strings.optional(),
      'title_contains': Ack.string().minLength(1).optional(),
      'description_contains': Ack.string().minLength(1).optional(),
    }).optional(),
    'select': Ack.list(
      Ack.enumString(wayfinderQueryColumns),
    ).unique().optional(),
    'order_by': Ack.list(
      Ack.object({
        'field': Ack.enumString(wayfinderQuerySortFields),
        'direction': Ack.enumString(['asc', 'desc']).optional(),
      }),
    ).optional(),
    'group_by': Ack.enumString(['type', 'effective_status']).optional(),
  }).optional(),
  'saved': Ack.string().minLength(1).optional(),
  'offset': Ack.integer().min(0).optional().withDefault(0),
  'limit': Ack.integer().min(1).max(1000).optional().withDefault(100),
});
